# Changelog

## 0.2.4
- Added automatic Immich External Library detection via the Immich API.
- Lets users choose from detected import paths instead of assuming `/external/fotos`.
- Added port availability checks for the Toolbox Dashboard, Pet Tagger, and Power Tools.
- Suggests the next free port when a default port is already in use.
- Validates the entered Immich API key before installation.
- Clarified that one shared `Immich Toolbox` API key is used by all selected modules.
- Improved the built-in dashboard and module links.
- Kept safe Folder → Album defaults (`MODE=CREATE`, `SYNC_MODE=0`).

## 0.2.3
- Added Immich URL autodetection.
- Added direct link to Immich API-key settings.
- Added internal vs browser/external Immich URL handling.
- Added an always-included Toolbox Dashboard.

## 0.2.2
- Fixed premature installer exit when optional modules were disabled under `set -e`.

## 0.2.1
- Improved API permission guidance.
- Pet Tagger permissions are listed explicitly.
- Power Tools selection now clearly recommends `Select all`.

## 0.2.0
- Added language selection: English, Nederlands, Deutsch.
- Added guided module selection and API-key permission help.

## 0.1.0
- Initial universal TrueNAS shell installer.
- Optional Folder → Album Sync.
- Optional Immich Pet Tagger.
- Optional Immich Power Tools (advanced).
- Creates selected modules under one `immichtoolbox` TrueNAS Custom App.
- No user-specific addresses, API keys, paths, or credentials are embedded.
