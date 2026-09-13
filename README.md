# Immich Toolbox for TrueNAS

A small **community orchestration project** that installs optional Immich companion tools as **one TrueNAS Custom App**.

> This project does not replace or fork Immich and does not bundle the source code of the upstream tools. It orchestrates their published container images and keeps attribution to each project.

## Modules in v0.1.0

### Folder → Album Sync
Uses [Salvoxia/immich-folder-album-creator](https://github.com/Salvoxia/immich-folder-album-creator).

Designed for Immich external libraries where filesystem folders should also appear as Immich albums.

Safe defaults:
- `MODE=CREATE`
- `SYNC_MODE=0`
- no cleanup/delete automation

### Pet Tagger
Uses [tedornitier/immich-pet-tagger](https://github.com/tedornitier/immich-pet-tagger).

Adds locally-trained pet recognition to Immich and exposes the upstream web UI.

### Immich Power Tools (advanced / optional)
Uses [immich-power-tools/immich-power-tools](https://github.com/immich-power-tools/immich-power-tools).

Provides bulk people management, album tools, analytics, duplicate tooling and workflows. It needs access to the Immich PostgreSQL database, so this module is **off by default**. The installer attempts to detect an official TrueNAS Immich database container/network, but asks for confirmation of the DB settings.

## One-line installation

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Kevin2296/immich-toolbox/main/install.sh)
```

For a local copy:

```bash
chmod +x install.sh
./install.sh
```

## Why a shell installer?

TrueNAS Custom Apps are easy to create through the middleware API, but their UI metadata is intentionally generic. The shell installer gives a simple interactive setup while still creating **one real app under Apps → Installed Applications**.

A later release can additionally ship the TrueNAS Community Catalog packaging (`questions.yaml`, `app.yaml`, etc.) so the same project can be submitted to the official TrueNAS Apps catalog.

## API permissions

The installer prints the permissions required by the selected modules before it asks for the API key.

For Power Tools, use a dedicated API key with the permissions recommended by that upstream project.

## Privacy / secrets

No personal server address, API key, pet name, folder name, or password is hardcoded in this repository.

The installer stores the values in the generated TrueNAS Custom App configuration. Do not post exported app configuration publicly because it may contain API/database credentials.

## Planned modules / ideas

Good future candidates:
- External-library helpers (favorites/metadata sync)
- Reverse-geocoding helpers
- Face/album automation
- Safe duplicate *review* utilities
- Backup/export helpers
- optional Immich Kiosk / display tools (probably a separate category)

The goal is not to duplicate features already built into Immich.

## Upstream projects

Immich Toolbox is an independent community project and is not affiliated with Immich, TrueNAS, or the upstream companion-tool authors.

Please report issues in the correct project:
- Toolbox installation/orchestration issues → this project
- Folder Album Creator logic → upstream Folder Album Creator
- Pet recognition behavior → upstream Pet Tagger
- Power Tools features → upstream Immich Power Tools
