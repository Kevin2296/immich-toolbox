# Immich Toolbox for TrueNAS

A community installer that bundles optional Immich companion tools into **one TrueNAS Custom App** with a lightweight dashboard.

> This project does not replace or fork Immich and does not bundle the source code of upstream tools. It orchestrates their published container images and keeps attribution to each project.

## Current version: v0.5.0

### Included modules

- **Folder → Album Sync** using [Salvoxia/immich-folder-album-creator](https://github.com/Salvoxia/immich-folder-album-creator)
- **Pet Tagger** using [tedornitier/immich-pet-tagger](https://github.com/tedornitier/immich-pet-tagger)
- **Immich Power Tools** using [immich-power-tools/immich-power-tools](https://github.com/immich-power-tools/immich-power-tools)
- **Toolbox Dashboard** (always included)

## One-line installation

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Kevin2296/immich-toolbox/main/install.sh)
```

## Existing installations

Running the installer again detects an existing `immichtoolbox` installation and offers:

1. **Update** — preserve current configuration and Toolbox data
2. **Reconfigure** — walk through the settings again
3. **Remove** — remove the Toolbox, with a separate choice to keep or remove managed volumes
4. **Quit**

A normal update reads the existing API key, Immich URLs, ports, Folder Albums settings, Pet Tagger settings and Power Tools database settings from the running Toolbox containers where possible.

## Dashboard

The dashboard defaults to port `30042` and provides:

- Immich and API-key links
- Pet Tagger and Power Tools launch buttons
- Folder → Album configuration details
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

The current installer deploys Immich Toolbox as a **TrueNAS Custom App**. This means the TrueNAS app details screen still shows generic Custom App metadata/icon even though the Toolbox dashboard has its own branding.

A native TrueNAS Community Catalog package is the next major packaging step; that is what enables first-class TrueNAS metadata, icon, source/homepage, web portal and native app version presentation.

## Privacy / secrets

No personal server address, API key, pet name, library path, or database password is hardcoded in this repository.

The generated TrueNAS Custom App configuration contains credentials required by the selected services, so do not post exported app configuration publicly.

## Upstream projects

Immich Toolbox is an independent community project and is not affiliated with Immich, TrueNAS, or the upstream companion-tool authors.
