#!/usr/bin/env bash
set -Eeuo pipefail

# Immich Toolbox bootstrap v0.4.1
# Loads the tested v0.4.0 installer and applies the TrueNAS app.update payload fix.

BASE_COMMIT="4af57763fd925c443e07bb0e96eeb1e5d0326f1d"
RAW_URL="https://raw.githubusercontent.com/Kevin2296/immich-toolbox/${BASE_COMMIT}/install.sh"
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

command -v curl >/dev/null 2>&1 || { echo "curl is required" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 is required" >&2; exit 1; }

curl -fsSL "$RAW_URL" -o "$TMP"

python3 - "$TMP" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text()
s = s.replace('TOOLBOX_VERSION="0.4.0"', 'TOOLBOX_VERSION="0.4.1"', 1)
old = "d=json.load(open(sys.argv[1])); d.pop('app_name',None); print(json.dumps(d))"
new = "d=json.load(open(sys.argv[1])); d.pop('app_name',None); d.pop('custom_app',None); print(json.dumps(d))"
if old not in s:
    raise SystemExit("Unable to apply v0.4.1 app.update payload fix")
s = s.replace(old, new, 1)
p.write_text(s)
PY

chmod +x "$TMP"
exec bash "$TMP"
