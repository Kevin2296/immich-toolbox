# Immich Toolbox for TrueNAS

A community installer that bundles optional Immich companion tools into **one TrueNAS Custom App** with a lightweight dashboard.

> This project does not replace or fork Immich and does not bundle the source code of upstream tools. It orchestrates their published container images and keeps attribution to each project.

## Current stable version: v1.0.0

### Included modules

- **Folder → Album Sync** using [Salvoxia/immich-folder-album-creator](https://github.com/Salvoxia/immich-folder-album-creator)
- **Pet Tagger** using [tedornitier/immich-pet-tagger](https://github.com/tedornitier/immich-pet-tagger)
- **Immich Power Tools** using [immich-power-tools/immich-power-tools](https://github.com/immich-power-tools/immich-power-tools)
- **Toolbox Dashboard** (always included)

## Stable one-line installation

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Kevin2296/immich-toolbox/v1.0.0/install.sh)
```

For development/testing, `main` may contain newer changes (currently v1.1.0, see [CHANGELOG](CHANGELOG.md)):

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

## Dashboard

The dashboard defaults to port `30042` and provides:

- Immich and API-key links
- Pet Tagger and Power Tools launch buttons
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

### Immich Power Tools

When Power Tools is enabled, the installer recommends **Select all / all API permissions** for the shared Toolbox API key.

## Folder → Album safety defaults

Folder → Album Sync is configured with:

```text
MODE=CREATE
SYNC_MODE=0
```

The Toolbox does not enable automated cleanup/delete behavior by default.

## Default ports

- Dashboard: `30042`
- Pet Tagger: `2287`
- Power Tools: `8001`

If a default port is occupied during a fresh installation/reconfigure, the installer suggests the next available port.

## TrueNAS UI note

The v1.0.0 installer deploys Immich Toolbox as a **TrueNAS Custom App**. This means the TrueNAS app details screen still shows generic Custom App metadata/icon even though the Toolbox dashboard has its own branding.

A native TrueNAS Community Catalog package is planned as a separate packaging track. That is what will enable first-class TrueNAS metadata, icon, source/homepage, web portal and native app version presentation. v1.0.0 itself is not yet installable directly from the official TrueNAS Community catalog.

## Privacy / secrets

No personal server address, API key, pet name, library path, or database password is hardcoded in this repository.

The installer sends the API key to `curl` on stdin, so it does not appear in the process list or in terminal output.

The generated TrueNAS Custom App configuration contains credentials required by the selected services, so do not post exported app configuration publicly.

## Upstream projects

Immich Toolbox is an independent community project and is not affiliated with Immich, TrueNAS, or the upstream companion-tool authors.
