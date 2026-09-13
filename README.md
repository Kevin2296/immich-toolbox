# Immich Toolbox for TrueNAS

A community installer that bundles optional Immich companion tools into **one TrueNAS Custom App** with a small launcher dashboard.

> This project does not replace or fork Immich and does not bundle the source code of upstream tools. It orchestrates their published container images and keeps attribution to each project.

## Current version: v0.2.4

### Included modules

- **Folder → Album Sync** using [Salvoxia/immich-folder-album-creator](https://github.com/Salvoxia/immich-folder-album-creator)
- **Pet Tagger** using [tedornitier/immich-pet-tagger](https://github.com/tedornitier/immich-pet-tagger)
- **Immich Power Tools** using [immich-power-tools/immich-power-tools](https://github.com/immich-power-tools/immich-power-tools)
- **Toolbox Dashboard** (always included)

## One-line installation

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Kevin2296/immich-toolbox/main/install.sh)
```

## What the installer does

- language selection: English / Nederlands / Deutsch
- detects the local Immich TrueNAS container and host port when possible
- asks for the browser/external Immich URL and derives the API URL
- shows a direct link to Immich API-key settings
- explains the permissions needed by the selected modules
- uses **one API key named `Immich Toolbox`** for all selected modules
- validates the API key before installation
- detects Immich External Libraries via `GET /api/libraries`
- lets you choose a detected import path for Folder → Album Sync
- checks whether dashboard/module ports are already in use
- suggests another free port when a default is occupied
- attempts to detect the Immich PostgreSQL container/network for Power Tools
- creates one TrueNAS Custom App named `immichtoolbox`

## Dashboard

The installer includes a lightweight dashboard, default port `30042`.

It links to:

- Immich
- Immich API-key settings
- Pet Tagger (when enabled)
- Immich Power Tools (when enabled)
- Folder → Album Sync information

The dashboard is currently a launcher/status page, not yet a full settings editor.

## API permissions

### Folder → Album Sync

- `asset.read`
- `album.read`
- `album.create`
- `album.update`
- `albumAsset.create`

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

## External Libraries

The installer tries to list the External Libraries configured in Immich and presents their `importPaths` for selection. It does **not** assume that `/external/fotos` exists on other systems.

If automatic detection fails, the installer asks for the path manually.

## Port handling

Defaults:

- Dashboard: `30042`
- Pet Tagger: `2287`
- Power Tools: `8001`

Before installation, the script checks whether each selected port is already listening on the TrueNAS host. If a default port is occupied, it suggests the next available port.

## Internal vs browser URL

The installer distinguishes between:

- **Browser/external URL** — the address you use to open Immich, for example `https://photos.example.com`
- **Internal container URL** — used by Toolbox containers to reach Immich locally, commonly `http://host.docker.internal:<Immich port>` on TrueNAS

The internal URL can be overridden in advanced mode.

## Privacy / secrets

No personal server address, API key, pet name, library path, or database password is hardcoded in this repository.

The generated TrueNAS Custom App configuration can contain credentials, so do not post exported app configuration publicly.

## Upstream projects

Immich Toolbox is an independent community project and is not affiliated with Immich, TrueNAS, or the upstream companion-tool authors.

Please report module-specific bugs upstream where appropriate.
