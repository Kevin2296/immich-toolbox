#!/usr/bin/env bash
set -Eeuo pipefail

# Immich Toolbox bootstrap v0.2.5
# Loads the tested v0.2.4 installer core and applies the v0.2.5 hotfix before execution.
# The hotfix sends warning/status text to stderr so command substitutions only capture
# machine-readable values such as selected port numbers.

BASE_COMMIT="a1a0f6423deeea11d6640876191a5d3e0a6079c7"
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
s = s.replace('TOOLBOX_VERSION="0.2.4"', 'TOOLBOX_VERSION="0.2.5"', 1)
old = '''warn(){ printf '%s!%s %s\\n' "$YELLOW" "$RESET" "$*"; }'''
new = '''warn(){ printf '%s!%s %s\\n' "$YELLOW" "$RESET" "$*" >&2; }'''
if old not in s:
    raise SystemExit("Unable to apply v0.2.5 port-output hotfix")
s = s.replace(old, new, 1)
p.write_text(s)
PY

chmod +x "$TMP"
exec bash "$TMP"
