# Changelog

## 0.5.0
- Polished the installer/update UX and terminal output.
- Added a concise post-install/update status screen with URLs and container states.
- Localized key update/status headings for English, Dutch and German.
- Added a browser-tab favicon for the Toolbox dashboard.
- Dashboard now shows common Folder → Album schedules in human-readable form.
- Dashboard update checks use `version.txt` instead of parsing the bootstrap script.
- Successful TrueNAS middleware JSON output stays hidden; actual errors are still shown.
- Keeps safe in-place update behavior and preserves existing configuration/data.

## 0.4.2
- Added browser favicon support.
- Fixed dashboard update-check version detection.
- Suppressed the very large successful TrueNAS middleware JSON response.

## 0.4.1
- Fixed TrueNAS `app.update` payload validation by removing create-only `custom_app` from update requests.

## 0.4.0
- Added update, reconfigure, remove and quit modes for existing installations.
- Existing API key, URLs, ports and module settings are read from current containers during update.
- Existing Folder Albums root, level and schedule are preserved during normal updates.
- Existing Pet Tagger and Power Tools configuration/data are preserved during normal updates.
- Added Toolbox removal with keep-data or remove-data choices.
- Reworked the dashboard into a richer configuration/status overview.

## 0.3.0
- Added safe in-place updates when `immichtoolbox` already exists.
- Existing Toolbox named volumes/data are preserved during updates; the app is no longer deleted/recreated by default.
- Existing Dashboard, Pet Tagger and Power Tools ports are detected and can be reused during an update.
- Rebuilt the Toolbox Dashboard with a cleaner responsive layout and detailed module information.
- Folder → Album Sync is now shown as a background service instead of a fake clickable tool.
- Dashboard shows External Library/root, album level, schedule, CREATE-only mode and thumbnail mode.
- Dashboard shows Pet Tagger and Power Tools ports/URLs plus access notes.
- Added a fuller terminal summary after installation/update, including URLs, access/login information and where to find logs.
- Added automatic TrueNAS timezone detection instead of hardcoding Europe/Amsterdam.

## 0.2.5
- Fixed port auto-selection output being mixed with warning text, which caused selected ports to fail integer parsing.

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
