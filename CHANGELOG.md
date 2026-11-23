# Changelog

## 1.5.3 (2026-11-23)
- Memory limits (`mem_limit`) for every Toolbox container: dashboard 64 MB, control 128 MB, folderalbums 512 MB, facealbums 512 MB, powertools 512 MB, pettagger 2 GB. They are caps well above normal use, so no container can take the whole NAS. Existing installations get them with a normal Update or the auto-update cron job.

## 1.5.2 (2026-11-23)
- Pet Tagger: `MALLOC_ARENA_MAX=2` and `MALLOC_TRIM_THRESHOLD_=131072` so Python gives memory back after a scan. On one NAS, Pet Tagger stayed at ~1.2 GB after a scan and dropped to ~380 MB after a restart.

## 1.5.1 (2026-11-23)
- Fixed Reconfigure: the ports of the Toolbox's own Dashboard, Pet Tagger and Power Tools were treated as "already in use". The installer then suggested another port, or stopped when you kept the current one. The current ports are now the default and are accepted.
- Reconfigure keeps the current Folder → Album root path, album level and schedule as defaults (Enter = keep).

## 1.5.0 (2026-11-23)
- Dashboard tabs: **Pet Tagger** and **Power Tools** open inside the dashboard (embedded), with an "Open in new window" button per tool. Tabs only appear for enabled modules and are remembered in the URL (`#pet`, `#power`).
- Immich and the API-key page now always open in a new browser tab.
- Embedded tools use the address you opened the dashboard with, so they also work when you use another IP or hostname for the NAS.

## 1.4.1 (2026-11-23)
- Face → Album setup: pressing Enter at "People for this album" now skips Face → Album (or finishes when albums were already added) instead of asking again forever.

## 1.4.0 (2026-11-23)
- **Dashboard module switches with "Sign in with Immich"**: Immich administrators can switch Folder → Album, Pet Tagger, Power Tools and Face → Album on or off on the dashboard, and pick people/albums for Face → Album there. Other Immich users can only look.
- New `control` service (`python:3.12-alpine`, no published port, no TrueNAS/Docker access). It checks logins against Immich (`/api/auth/login`, admin only, login token ended right away). Sessions are HttpOnly + SameSite=Strict cookies, with a CSRF header and a login rate limit. If the dashboard runs under the same host as Immich, you are signed in automatically from the Immich session.
- New `--apply-request` mode and TrueNAS cron job `Immich Toolbox dashboard changes` (every minute, only acts when a request is waiting, with a lock). It applies the request with the normal update flow and reports the status back to the dashboard.
- The installer asks whether to enable module switches (default yes; Reconfigure shows the current state). Removing the Toolbox also removes this cron job.
- Dashboard API paths are relative, so the dashboard also works under a sub-path behind a reverse proxy.

## 1.3.3 (2026-11-23)
- Reconfigure (option 2) now shows which modules are currently on or off, and Enter keeps the current state. Before, every module defaulted to Yes.
- Reconfigure reuses the existing API key and Immich URL: press Enter to keep the key.
- The module list is translated.

## 1.3.2 (2026-11-23)
- Fixed: with many TrueNAS apps the existing-installation check failed with `python3: Argument list too long`, so the installer started a fresh install instead of offering Update, and `--update --yes` (cron job) stopped with "not installed yet". The app list is now passed on stdin.

## 1.3.1 (2026-11-23)
- The installer now stops with a clear message when Docker is not running or `midclt call app.query` fails. Before, it could not see the existing installation and started a fresh install instead of offering Update.
- All module questions now default to Yes (just press Enter to install everything) and are translated.
- Stable installation branch `v1.3.1`.

## 1.3.0 (2026-11-23)
- Stable installation branch `v1.3.0`; the README one-line installer now points to it.
- New module **Face → Album** using [romainrbr/immich-face-to-album](https://github.com/romainrbr/immich-face-to-album) (`rbrucker/immich-face-to-album:1.0.17`): auto-updating albums per person or group of people.
- The installer lists named people and albums through the Immich API, can create a new album and supports several face albums with "any" or "all together" matching.
- One `facealbums` container syncs all rules (default every 60 minutes, incremental after the first run). Rules are kept on update/unattended update and shown on the dashboard.

## 1.2.0 (not released separately, included in 1.3.0)
- New `--update --yes` mode for unattended updates (plus `--lang` and `--help`). It never prompts, never stops other apps and never changes `ROOT_PATH`; it only reports problems.
- Optional TrueNAS cron job `Immich Toolbox auto-update` (weekly or daily), offered at the end of an interactive run and removed together with the Toolbox.
- Updates now pull the module images again and redeploy only when a container still runs an older image, so floating tags (`pet-tagger:cpu`, `nginx:alpine`) pick up upstream releases.
- Folder → Album creator `1.0.0` → `2.0.3` (same environment variables; upstream images follow the latest Immich API).
- Immich Power Tools `v0.22.0` → `v0.26.0` (same environment variables).
- `app.update`/`app.create` failures now stop the installer with a clear message.

## 1.1.0
- `install.sh` is now self-contained: the bootstrap no longer downloads the v0.4.0 core and patches it at runtime.
- Folder → Album Sync: `ROOT_PATH` is chosen from the External Library import paths reported by `GET /api/libraries`; multiple paths are supported (comma separated). HTTP 401/403 is explained (admin key with `library.read` needed) and the Immich container mounts are shown as a hint. Manually entered paths are checked against the import paths.
- Update mode re-checks the stored `ROOT_PATH` and offers to fix a mismatch (cause of `0 albums created`).
- The dashboard shows the configured root path(s) and whether they match an Immich import path.
- Detects other TrueNAS apps (e.g. `immichalbums`) or stray containers running `immich-folder-album-creator` and offers to stop the duplicate app.
- Pet Tagger: dashboard button for a one-time full scan of existing photos (`POST /api/scan`) with live status; the installer offers it on update when pets with references exist.
- Dashboard nginx answers `/stub_status`, `/basic_status`, `/nginx_status` (Netdata) and silences other common probe URLs instead of logging 404s.
- The API key is passed to `curl` on stdin instead of the command line.
- Added `library.read` to the documented Folder → Album permissions.

## 1.0.0
- First stable Immich Toolbox release.
- Promoted the tested Custom App installer flow to v1.0.0.
- Keeps safe in-place update behavior and preserves existing configuration/data by default.
- Includes Folder → Album Sync, Pet Tagger, Immich Power Tools and the Toolbox Dashboard under one TrueNAS app.
- Includes browser favicon, update checking, human-readable schedules and concise post-install/update status output.
- Localized the most visible update prompts for English, Dutch and German.
- Added a stable `v1.0.0` installation branch so the documented installer URL no longer depends on moving `main` content.
- Native TrueNAS Community Catalog packaging remains a separate next step; v1.0.0 is still deployed as a TrueNAS Custom App.

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
