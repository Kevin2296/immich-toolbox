#!/usr/bin/env python3
"""Weekly upstream check for the pinned module images in install.sh.

Upstream tools usually release a new version after a (big) Immich update.
For every pinned module this script compares the pin with the latest GitHub
release of the upstream project and checks that the matching image exists.

* Patch/minor updates (same first version number) are combined in one PR,
  which also bumps the Toolbox patch version and CHANGELOG. When bash -n and
  shellcheck pass, the PR is merged automatically, so installations with the
  auto-update cron job pick it up on their next run.
* Major updates (first version number changes, e.g. 2.x -> 3.0) get their own
  PR per module and are never merged automatically.

Runs in GitHub Actions (.github/workflows/upstream-updates.yml). Local test:
  DRY_RUN=1 SKIP_IMAGE_CHECK=1 python3 .github/scripts/upstream_updates.py
DRY_RUN only edits the working tree; nothing is committed or pushed.
"""
import datetime
import json
import os
import re
import subprocess
import sys
import tempfile
import time
import urllib.request

# (variable in install.sh, image without tag, GitHub repo, display name)
MODULES = [
    ("FOLDER_IMAGE", "salvoxia/immich-folder-album-creator", "Salvoxia/immich-folder-album-creator", "Folder → Album"),
    ("POWER_IMAGE", "ghcr.io/immich-power-tools/immich-power-tools", "immich-power-tools/immich-power-tools", "Power Tools"),
    ("FACE_IMAGE", "rbrucker/immich-face-to-album", "romainrbr/immich-face-to-album", "Face → Album"),
]
DRY_RUN = os.environ.get("DRY_RUN") == "1"
SKIP_IMAGE_CHECK = os.environ.get("SKIP_IMAGE_CHECK") == "1"


def gh_api(path):
    headers = {"Accept": "application/vnd.github+json", "User-Agent": "immich-toolbox-upstream-check"}
    if os.environ.get("GH_TOKEN"):
        headers["Authorization"] = "Bearer " + os.environ["GH_TOKEN"]
    with urllib.request.urlopen(urllib.request.Request("https://api.github.com/" + path, headers=headers), timeout=30) as r:
        return json.load(r)


def version(tag):
    m = re.fullmatch(r"v?(\d+)\.(\d+)\.(\d+)", tag or "")
    return tuple(int(x) for x in m.groups()) if m else None


def run(*args, check=True):
    print("+", " ".join(args), flush=True)
    return subprocess.run(args, check=check, text=True, capture_output=True)


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def write(path, text):
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)


def image_exists(ref):
    return SKIP_IMAGE_CHECK or run("docker", "manifest", "inspect", ref, check=False).returncode == 0


def find_updates():
    src = read("install.sh")
    updates = []
    for var, image, repo, name in MODULES:
        m = re.search(rf'^{var}="{re.escape(image)}:([^"]+)"', src, re.M)
        if not m:
            print(f"::warning::{var} not found in install.sh")
            continue
        current = m.group(1)
        release = gh_api(f"repos/{repo}/releases/latest")
        latest = release.get("tag_name", "")
        if not version(current) or not version(latest):
            print(f"::warning::{name}: cannot compare '{current}' with '{latest}'")
            continue
        if version(latest) <= version(current):
            print(f"{name}: {current} is up to date")
            continue
        if not image_exists(f"{image}:{latest}"):
            print(f"::warning::{name}: release {latest} has no image {image}:{latest} yet")
            continue
        updates.append({
            "var": var, "image": image, "repo": repo, "name": name,
            "old": current, "new": latest, "url": release.get("html_url", f"https://github.com/{repo}/releases"),
            "major": version(latest)[0] != version(current)[0],
        })
        print(f"{name}: {current} -> {latest}{' (MAJOR)' if updates[-1]['major'] else ''}")
    return updates


def apply_pins(updates):
    for path in ("install.sh", "README.md"):
        text = read(path)
        for u in updates:
            text = text.replace(f"{u['image']}:{u['old']}", f"{u['image']}:{u['new']}")
        write(path, text)


def bump_toolbox_version(updates):
    src = read("install.sh")
    a, b, c = map(int, re.search(r'^TOOLBOX_VERSION="(\d+)\.(\d+)\.(\d+)"', src, re.M).groups())
    new = f"{a}.{b}.{c + 1}"
    write("install.sh", re.sub(r'^TOOLBOX_VERSION="[^"]+"', f'TOOLBOX_VERSION="{new}"', src, count=1, flags=re.M))
    write("version.txt", new + "\n")
    lines = "".join(f"- {u['name']} `{u['old']}` → `{u['new']}` (automatic upstream update, [release notes]({u['url']})).\n" for u in updates)
    entry = f"## {new} ({datetime.date.today().isoformat()})\n{lines}\n"
    write("CHANGELOG.md", read("CHANGELOG.md").replace("# Changelog\n\n", "# Changelog\n\n" + entry, 1))
    return new


def checks_pass():
    ok = run("bash", "-n", "install.sh", check=False).returncode == 0
    sc = run("shellcheck", "-S", "error", "install.sh", check=False)
    if sc.returncode != 0:
        print(sc.stdout + sc.stderr)
    return ok and sc.returncode == 0


def immich_latest():
    try:
        return gh_api("repos/immich-app/immich/releases/latest").get("tag_name", "unknown")
    except Exception:  # informational only
        return "unknown"


def pr_body(updates, auto, passed):
    rows = "".join(f"| {u['name']} | `{u['old']}` | `{u['new']}` | [{u['repo']}]({u['url']}) |\n" for u in updates)
    if auto and passed:
        note = "Patch/minor update(s): checks passed, so this PR is merged automatically. Installations with the auto-update cron job pick it up on their next run."
    elif auto:
        note = "**Checks failed**, so this PR was not merged. See the workflow log."
    else:
        note = ("**Major update**: not merged automatically. Read the upstream release notes "
                "(new environment variables? minimum Immich version?) and test before merging. "
                "This PR is refreshed by the weekly run while it stays open.")
    return (f"Automatic upstream check. Latest Immich release: `{immich_latest()}`.\n\n"
            f"| Module | Current | New | Release |\n|---|---|---|---|\n{rows}\n{note}\n\n"
            f"Checks (`bash -n`, `shellcheck -S error`): {'passed' if passed else 'FAILED'}.\n")


def publish(branch, base_sha, title, body, merge):
    """Commit the working tree to `branch` (recreated from base_sha), open or update its PR, optionally merge."""
    run("git", "switch", "-C", branch)
    run("git", "add", "-A")
    run("git", "commit", "-m", title)
    run("git", "push", "--force", "origin", f"HEAD:refs/heads/{branch}")
    with tempfile.NamedTemporaryFile("w", suffix=".md", delete=False, encoding="utf-8") as f:
        f.write(body)
    existing = json.loads(run("gh", "pr", "list", "--head", branch, "--state", "open", "--json", "number").stdout or "[]")
    if existing:
        run("gh", "pr", "edit", str(existing[0]["number"]), "--title", title, "--body-file", f.name)
    else:
        run("gh", "pr", "create", "--base", "main", "--head", branch, "--title", title, "--body-file", f.name)
    merged = not merge
    if merge:
        for _ in range(6):
            if run("gh", "pr", "merge", branch, "--merge", "--delete-branch", check=False).returncode == 0:
                merged = True
                break
            time.sleep(10)
        else:
            print(f"::error::Could not merge {branch}")
    # Next PR starts again from the original main commit.
    run("git", "switch", "--detach", base_sha)
    run("git", "reset", "--hard", base_sha)
    return merged


def main():
    updates = find_updates()
    if not updates:
        print("Everything is up to date.")
        return 0
    minor = [u for u in updates if not u["major"]]
    major = [u for u in updates if u["major"]]
    if DRY_RUN:
        apply_pins(minor)
        if minor:
            print("Toolbox version would become", bump_toolbox_version(minor))
        print("Major updates (separate PR, not merged):", [f"{u['name']} {u['new']}" for u in major])
        return 0

    run("git", "config", "user.name", "github-actions[bot]")
    run("git", "config", "user.email", "41898282+github-actions[bot]@users.noreply.github.com")
    base_sha = run("git", "rev-parse", "HEAD").stdout.strip()
    failed = False

    if minor:
        apply_pins(minor)
        new = bump_toolbox_version(minor)
        passed = checks_pass()
        title = f"Upstream updates → v{new}: " + ", ".join(f"{u['name']} {u['new']}" for u in minor)
        if not publish(f"upstream/auto-v{new}", base_sha, title, pr_body(minor, True, passed), merge=passed) or not passed:
            failed = True

    for u in major:
        apply_pins([u])
        passed = checks_pass()
        title = f"Major upstream update: {u['name']} {u['old']} → {u['new']} (review needed)"
        publish(f"upstream/major-{u['var'].lower()}", base_sha, title, pr_body([u], False, passed), merge=False)

    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
