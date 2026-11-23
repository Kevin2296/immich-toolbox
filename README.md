# Immich Toolbox for TrueNAS

A community installer that bundles optional Immich companion tools into **one TrueNAS Custom App** with a lightweight dashboard.

> This project does not replace or fork Immich and does not bundle the source code of upstream tools. It orchestrates their published container images and keeps attribution to each project.

## Current stable version: v1.5.3

### Included modules

- **Folder → Album Sync** using [Salvoxia/immich-folder-album-creator](https://github.com/Salvoxia/immich-folder-album-creator)
- **Pet Tagger** using [tedornitier/immich-pet-tagger](https://github.com/tedornitier/immich-pet-tagger)
- **Immich Power Tools** using [immich-power-tools/immich-power-tools](https://github.com/immich-power-tools/immich-power-tools)
- **Face → Album** using [romainrbr/immich-face-to-album](https://github.com/romainrbr/immich-face-to-album)
- **Toolbox Dashboard** (always included), optionally with **module switches after "Sign in with Immich"**

## Stable one-line installation

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Kevin2296/immich-toolbox/v1.5.3/install.sh)
```

For development/testing, `main` may contain newer changes (see [CHANGELOG](CHANGELOG.md)):

```bash
bash <(curl -fsSL "https://raw.githubusercontent.com/Kevin2296/immich-toolbox/main/install.sh?cb=$(date +%s)")
```

## Existing installations

Running the installer again detects an existing `immichtoolbox` installation and offers:

1. **Update** — preserve current configuration and Toolbox data
2. **Reconfigure** — walk through the settings again
3. **Remove** — remove the Toolbox, with a separate choice to keep or remove managed volumes
4. **Quit**

A normal update reads the existing API key, Immich URLs, ports, Folder Albums settings, Pet Tagger settings and Power Tools database settings from the running Toolbox containers where possible.

Every update also pulls the module images again. Containers that still run an older image afterwards (e.g. a new `pet-tagger:cpu` or `nginx:alpine` release) are redeployed; otherwise nothing restarts needlessly.

## Automatic updates

TrueNAS has no update button for Custom Apps that changes their configuration, so updates come from re-running the installer. This can run unattended:

```bash
install.sh --update --yes [--lang en|nl|de]
```

`--update --yes` keeps all settings and never asks anything. It also **never stops other apps and never changes `ROOT_PATH` by itself**: it only reports problems (as warnings on stderr) and leaves fixing them to an interactive run. It exits with an error if the existing API key or root path cannot be read.

At the end of an interactive install/update the installer offers to create a TrueNAS cron job (**System → Advanced → Cron Jobs → `Immich Toolbox auto-update`**, weekly on Sunday 04:00 or daily at 04:00, as root). The job downloads the latest `install.sh` from `main` and runs it with `--update --yes`. Standard output is hidden; warnings and errors go to TrueNAS's root e-mail if mail is configured. Removing the Toolbox (option 3) also removes the cron job.

> The cron job runs whatever is on `main` of this repository as root on your NAS. Only enable it if you trust who can push to `main`.

### Where module updates come from

| Module | Image tag | How it updates |
|---|---|---|
| Dashboard | `nginx:alpine` | floating tag: every update run pulls the newest image |
| Pet Tagger | `ghcr.io/tedornitier/immich-pet-tagger:cpu` | floating tag: every update run pulls the newest image |
| Dashboard control | `python:3.12-alpine` | floating tag (Python 3.12 patch releases): every update run pulls the newest image |
| Folder → Album | `salvoxia/immich-folder-album-creator:2.0.3` | pinned: checked weekly (see below), then rolled out by the next update run |
| Power Tools | `ghcr.io/immich-power-tools/immich-power-tools:v0.26.0` | pinned, same as above |
| Face → Album | `rbrucker/immich-face-to-album:1.0.17` | pinned, same as above |

Upstream tools usually publish a new release after a (big) Immich update. The [`Upstream updates`](.github/workflows/upstream-updates.yml) GitHub Action checks the pinned modules every Monday:

- **patch/minor** releases (e.g. `2.0.3` → `2.0.4` or `2.1.0`) are bumped in one PR together with a new Toolbox patch version. After `bash -n` and `shellcheck` pass, the PR is **merged automatically**, so the auto-update cron job installs it on its next run
- **major** releases (e.g. `2.x` → `3.0`) get their own PR that is **never merged automatically**: read the upstream release notes and merge it yourself
- an update is only proposed once the upstream image with that tag actually exists

The Action needs **Settings → Actions → General → Workflow permissions → "Read and write permissions"** and **"Allow GitHub Actions to create and approve pull requests"**. It can also be started by hand (Actions → Upstream updates → Run workflow).

Since v1.1.0 an update also **re-checks the Folder Albums `ROOT_PATH`** against the External Library import paths reported by Immich. If the stored path is not an import path (or a folder below one) — which makes the album creator log `0 albums created` on every run — the installer shows the mismatch and offers to pick the correct path(s).

## Folder → Album: choosing `ROOT_PATH`

The album creator only looks at assets whose Immich `originalPath` starts with `ROOT_PATH`, so `ROOT_PATH` must be **exactly the import path of an Immich External Library** as Immich sees it (inside the Immich container), e.g. `/mnt/Pool1/Photos` — not the path where you think the files live, and not an arbitrary placeholder such as `/external/fotos`.

The installer reads the import paths with `GET /api/libraries`:

- one library/import path is selected automatically; with several you choose `a` (all) or numbers such as `1,3`
- multiple paths are written as a comma-separated `ROOT_PATH` (supported by the album creator); paths that contain a comma cannot be used
- `GET /api/libraries` is **admin-only** and needs the `library.read` permission. Without it the installer explains the HTTP 401/403, lists the folders mounted into the Immich container as a hint and asks for the path manually
- the dashboard shows the configured path(s) and whether they were verified against Immich

## Duplicate album creator apps

If another TrueNAS app runs the same `immich-folder-album-creator` image (for example a separate app called `immichalbums`), both apps create the same albums. After installing/updating, the installer detects such apps via `midclt call app.query` and offers to **stop** them (they are not deleted). Album-creator containers started outside TrueNAS apps (Portainer, Dockge, `docker run`) are reported so you can stop them yourself.

## Pet Tagger: scanning existing photos

Pet Tagger's hourly background poll only processes assets uploaded **after** its previous poll (`Fetching assets taken after …` in the log), so photos that were already in Immich are never tagged automatically. Existing photos are tagged by a one-time manual scan (Pet Tagger API `POST /api/scan` with `scan_since`).

- A scan only makes sense once at least one pet has reference photos, so a fresh install does not start one; it tells you to enroll your pets first.
- The dashboard has a **Start full scan** button (with a "photos taken since" date), a stop button and live status.
- After an install/update, if pets with references already exist (update, or a kept `pettagger_data` volume), the installer offers to start the full scan right away (default: no — on CPU this can take hours).

## Dashboard: switch modules on/off ("Sign in with Immich")

With **module switches** enabled (the installer asks; default yes) the dashboard gets a **Modules** panel:

- **Sign in with Immich**: you sign in with your normal Immich e-mail and password. The dashboard asks Immich whether they are correct and whether you are an **Immich administrator**. Only administrators can change modules; other Immich users can only look. The Immich login token is ended right away; the dashboard keeps its own session cookie (HttpOnly, SameSite=Strict, 12 hours). After 5 wrong passwords from one address, login is blocked for 5 minutes.
- If the dashboard runs under the **same address as Immich** behind your reverse proxy (e.g. `https://immich.example.com/toolbox/`), the browser already sends your Immich login and you are signed in automatically.
- Switch Folder → Album, Pet Tagger, Power Tools and Face → Album on or off. For Face → Album you pick the people and the album (or a new album) on the page, just like in the installer.
- Data of switched-off modules (volumes) is kept.

How a change is applied:

1. The small `control` container (`python:3.12-alpine`, no published port; reachable only through the dashboard at `/control/api/`) writes the request to its `control_data` volume. It has **no access to TrueNAS or Docker**.
2. A TrueNAS cron job **`Immich Toolbox dashboard changes`** (System → Advanced → Cron Jobs, root, every minute) checks whether a request is waiting. Only then does it download the latest `install.sh` from `main` and run it with `--apply-request`. That works like `--update --yes` with the requested modules, so the installer's checks apply. A lock prevents two runs at the same time.
3. The dashboard shows "waiting / applying / done" and reloads when done. Errors (for example: Folder → Album cannot read the import paths) are shown on the dashboard and mailed by TrueNAS if mail is set up.

Newly switched-on modules get defaults: Folder → Album uses **all** External Library import paths (needs the admin key with `library.read`); Pet Tagger and Power Tools get the first free port from 2287 / 8001; Power Tools detects the Immich database. If that is not possible the change is refused with a message, and you enable the module once with the installer instead.

> The cron job runs the installer from `main` as root, like the auto-update job. Turn module switches off with installer option 2 if you do not want this.

## Dashboard

The dashboard defaults to port `30042` and provides:

- Immich and API-key links
- tabs that open **Pet Tagger** and **Power Tools inside the dashboard** (embedded), each with an "Open in new window" button; Immich itself always opens in a new browser tab. If a tool stays empty, it blocks embedding or the dashboard runs over https (the tools use http on their own ports); use the new-window button then
- Folder → Album configuration details, including the configured `ROOT_PATH`(s) and whether they match an Immich import path
- Pet Tagger full-scan (backfill) button with status
- quiet monitoring endpoints: `/stub_status`, `/basic_status` and `/nginx_status` return nginx `stub_status` (for Netdata and similar agents); other common probe URLs return 404 without being logged
- Toolbox version and update check
- configuration overview and security notes
- browser favicon / Toolbox branding

Folder → Album Sync is a background service and therefore does not have its own web interface.

## What the installer does

- language selection: English / Nederlands / Deutsch
- detects the local Immich TrueNAS container and host port when possible
- separates the browser/external Immich URL from the internal container URL
- shows a direct link to Immich API-key settings
- uses **one API key named `Immich Toolbox`** for all selected modules
- validates the API key on a new/reconfigured installation
- detects Immich External Libraries via the Immich API when possible
- preserves the existing Folder Albums root during normal updates
- checks dashboard/module ports and suggests a free port when necessary
- detects the Immich PostgreSQL container/network for Power Tools when possible
- creates or updates one TrueNAS Custom App named `immichtoolbox`
- keeps successful TrueNAS middleware JSON out of the terminal while still showing real errors

## API permissions

### Folder → Album Sync

- `asset.read`
- `album.read`
- `album.create`
- `album.update`
- `albumAsset.create`
- `library.read` — only used by the installer to read External Library import paths; requires the key of an **admin** user

### Pet Tagger

- `asset.read`
- `asset.view`
- `person.create`
- `person.read`
- `person.update`
- `person.delete`
- `person.reassign`
- `face.create`
- `face.read`
- `face.delete`

Optional review-tag permissions:

- `tag.create`
- `tag.asset`

### Face → Album

- `person.read` (also used by the dashboard face picker)
- `asset.read`
- `album.read`
- `albumAsset.create`
- `album.create` (only when the installer creates a new album for you)

### Immich Power Tools

When Power Tools is enabled, the installer recommends **Select all / all API permissions** for the shared Toolbox API key.

## Face → Album

Keeps Immich albums filled with every photo of one or more people (like Google Photos' auto-updating albums).

- During install/reconfigure the installer lists your **named** people (Immich → Explore → People) and your albums. Per album you pick the people (numbers like `1,3`), choose whether they must appear **together** or whether **any** of them is enough, and pick an existing album or let the installer create one.
- You can add several face albums. One `facealbums` container syncs them all, every 60 minutes by default. The first run scans everything; after that only new uploads are checked (state is kept in the `facealbums_state` volume).
- Photos are only added, never removed.
- To change people or albums, run the installer again and choose option 2 (Reconfigure). Normal and unattended updates keep the existing face albums.
- The dashboard lists every face album with a link to the album in Immich.

## Folder → Album safety defaults

Folder → Album Sync is configured with:

```text
MODE=CREATE
SYNC_MODE=0
```

The Toolbox does not enable automated cleanup/delete behavior by default.

## Memory limits

Every Toolbox container has a memory limit, set well above its normal use: dashboard 64 MB, control 128 MB, Folder → Album 512 MB, Face → Album 512 MB, Power Tools 512 MB, Pet Tagger 2 GB (it uses about 0.4 GB idle and about 1.4 GB while scanning).

## Default ports

- Dashboard: `30042`
- Pet Tagger: `2287`
- Power Tools: `8001`

If a default port is occupied during a fresh installation/reconfigure, the installer suggests the next available port.

## TrueNAS UI note

The installer deploys Immich Toolbox as a **TrueNAS Custom App**. This means the TrueNAS app details screen still shows generic Custom App metadata/icon even though the Toolbox dashboard has its own branding.

A native TrueNAS Community Catalog package is planned as a separate packaging track. That is what will enable first-class TrueNAS metadata, icon, source/homepage, web portal and native app version presentation. The Toolbox itself is not yet installable directly from the official TrueNAS Community catalog.

## Privacy / secrets

No personal server address, API key, pet name, library path, or database password is hardcoded in this repository.

The installer sends the API key to `curl` on stdin, so it does not appear in the process list or in terminal output.

The generated TrueNAS Custom App configuration contains credentials required by the selected services, so do not post exported app configuration publicly.

## Upstream projects

Immich Toolbox is an independent community project and is not affiliated with Immich, TrueNAS, or the upstream companion-tool authors.
