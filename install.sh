#!/usr/bin/env bash
set -Eeuo pipefail

APP_NAME="immichtoolbox"
TOOLBOX_VERSION="0.1.0"

# Pinned upstream versions for reproducible installs.
FOLDER_IMAGE="salvoxia/immich-folder-album-creator:1.0.0"
PET_IMAGE="ghcr.io/tedornitier/immich-pet-tagger:latest"
POWER_IMAGE="ghcr.io/immich-power-tools/immich-power-tools:v0.22.0"

BOLD=$'\033[1m'; DIM=$'\033[2m'
GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RED=$'\033[31m'; CYAN=$'\033[36m'; RESET=$'\033[0m'

say(){ printf '%s\n' "$*"; }
ok(){ printf '%s✓%s %s\n' "$GREEN" "$RESET" "$*"; }
warn(){ printf '%s!%s %s\n' "$YELLOW" "$RESET" "$*"; }
die(){ printf '%s✗%s %s\n' "$RED" "$RESET" "$*" >&2; exit 1; }

# When started through: bash <(curl ...)
# force interactive questions to the terminal instead of the downloaded script stream.
if [[ -r /dev/tty ]]; then
  exec </dev/tty
fi

[[ "$(uname -s)" == "Linux" ]] || die "Deze installer moet op TrueNAS SCALE / Community Edition draaien."
command -v midclt >/dev/null 2>&1 || die "midclt is niet gevonden. Start dit vanuit de TrueNAS shell."
command -v python3 >/dev/null 2>&1 || die "python3 ontbreekt."
command -v docker >/dev/null 2>&1 || die "docker ontbreekt."

if [[ $EUID -eq 0 ]]; then SUDO=""; else SUDO="sudo"; fi
$SUDO -v

clear || true
say "${BOLD}Immich Toolbox ${TOOLBOX_VERSION}${RESET}"
say "============================================================"
say "Eén TrueNAS Custom App met optionele Immich-uitbreidingen."
say
say "Ondersteund in deze eerste publieke versie:"
say "  ${CYAN}[1]${RESET} Folder → Album Sync   (external-library mappen naar albums)"
say "  ${CYAN}[2]${RESET} Pet Tagger            (huisdieren als People in Immich)"
say "  ${CYAN}[3]${RESET} Immich Power Tools    (beheer/workflows/duplicates; advanced)"
say
say "${DIM}Alles is modulair: je kunt 1, 2 of 3 onderdelen installeren.${RESET}"
say

ask_yes_no() {
  local prompt="$1" default="${2:-Y}" ans
  if [[ "$default" == "Y" ]]; then
    read -rp "$prompt [Y/n]: " ans
    ans="${ans:-Y}"
  else
    read -rp "$prompt [y/N]: " ans
    ans="${ans:-N}"
  fi
  [[ "$ans" =~ ^[YyJj]$ ]]
}

ENABLE_FOLDER=false
ENABLE_PET=false
ENABLE_POWER=false

ask_yes_no "Folder → Album Sync inschakelen?" Y && ENABLE_FOLDER=true
ask_yes_no "Pet Tagger inschakelen?" Y && ENABLE_PET=true
ask_yes_no "Immich Power Tools inschakelen? (advanced; DB-toegang nodig)" N && ENABLE_POWER=true

if ! $ENABLE_FOLDER && ! $ENABLE_PET && ! $ENABLE_POWER; then
  die "Er is geen module geselecteerd."
fi

say
say "${BOLD}Immich API-key${RESET}"
say "Maak één API-key voor deze Toolbox, of gebruik later per module aparte keys."
say
if $ENABLE_POWER; then
  say "Omdat Power Tools is geselecteerd: ${YELLOW}selecteer alle Immich API-permissies${RESET}."
else
  say "Selecteer minimaal de volgende rechten:"
  if $ENABLE_FOLDER; then
    say "  Folder Albums:"
    say "    • asset.read"
    say "    • album.read"
    say "    • album.create"
    say "    • album.update"
    say "    • albumAsset.create"
  fi
  if $ENABLE_PET; then
    say "  Pet Tagger:"
    say "    • asset.read"
    say "    • asset.view"
    say "    • person.create / person.read / person.update / person.delete / person.reassign"
    say "    • face.create / face.read / face.delete"
  fi
fi
say
read -rp "Druk op Enter zodra je de API-key hebt..." _

# Refuse to overwrite an existing toolbox automatically.
EXISTING="$($SUDO midclt call app.query 2>/dev/null || echo '[]')"
if python3 - "$APP_NAME" "$EXISTING" <<'PY'
import json, sys
name=sys.argv[1]
try: rows=json.loads(sys.argv[2])
except Exception: rows=[]
sys.exit(0 if any((r.get("id")==name or r.get("name")==name) for r in rows if isinstance(r,dict)) else 1)
PY
then
  die "De app '${APP_NAME}' bestaat al. Verwijder/update hem eerst bewust; deze installer overschrijft geen bestaande installatie."
fi

read -rsp "Immich API key: " API_KEY
say
[[ -n "$API_KEY" ]] || die "API-key mag niet leeg zijn."

# User-facing and container-facing URLs.
read -rp "TrueNAS / Immich IP of hostname (bijv. 192.168.1.10): " HOST_NAME
[[ -n "$HOST_NAME" ]] || die "Een host/IP is nodig."
read -rp "Immich hostpoort [30041]: " IMMICH_PORT
IMMICH_PORT="${IMMICH_PORT:-30041}"
IMMICH_BASE_URL="http://${HOST_NAME}:${IMMICH_PORT}"
IMMICH_API_URL="${IMMICH_BASE_URL}/api"
CONTAINER_IMMICH_BASE="http://host.docker.internal:${IMMICH_PORT}"
CONTAINER_IMMICH_API="${CONTAINER_IMMICH_BASE}/api"

say
if curl -fsS --max-time 5 "${IMMICH_API_URL}/server/ping" >/dev/null 2>&1; then
  ok "Immich reageert via ${IMMICH_API_URL}"
else
  warn "Immich ping via ${IMMICH_API_URL} kon niet worden bevestigd."
  ask_yes_no "Toch doorgaan?" N || exit 1
fi

# Compose model built by Python from a simple JSON config.
CFG="$(mktemp)"
PAYLOAD="$(mktemp)"
trap 'rm -f "$CFG" "$PAYLOAD"' EXIT

python3 - "$CFG" <<PY
import json
json.dump({
 "app_name": "$APP_NAME",
 "api_key": "$API_KEY",
 "immich_base": "$CONTAINER_IMMICH_BASE",
 "immich_api": "$CONTAINER_IMMICH_API",
 "external_immich": "$IMMICH_BASE_URL",
 "folder_image": "$FOLDER_IMAGE",
 "pet_image": "$PET_IMAGE",
 "power_image": "$POWER_IMAGE",
 "enable_folder": $ENABLE_FOLDER,
 "enable_pet": $ENABLE_PET,
 "enable_power": $ENABLE_POWER,
}, open("$CFG","w"))
PY

if $ENABLE_FOLDER; then
  say
  say "${BOLD}Folder → Album Sync${RESET}"
  read -rp "External Library root in Immich [/external/fotos]: " ROOT_PATH
  ROOT_PATH="${ROOT_PATH:-/external/fotos}"
  read -rp "Album level [1]: " ALBUM_LEVELS
  ALBUM_LEVELS="${ALBUM_LEVELS:-1}"
  say "Planning:"
  say "  1) Dagelijks 03:00"
  say "  2) Elke 6 uur"
  say "  3) Elk uur"
  say "  4) Eigen cron"
  read -rp "Keuze [1]: " SCHED; SCHED="${SCHED:-1}"
  case "$SCHED" in
    2) CRON_EXPRESSION="0 */6 * * *";;
    3) CRON_EXPRESSION="0 * * * *";;
    4) read -rp "Cron-expressie: " CRON_EXPRESSION;;
    *) CRON_EXPRESSION="0 3 * * *";;
  esac
  ask_yes_no "Direct na installatie album-sync starten?" Y && RUN_IMMEDIATELY=true || RUN_IMMEDIATELY=false
  ask_yes_no "Random album-thumbnail laten instellen?" Y && ALBUM_THUMB="random" || ALBUM_THUMB=""

  python3 - "$CFG" "$ROOT_PATH" "$ALBUM_LEVELS" "$CRON_EXPRESSION" "$RUN_IMMEDIATELY" "$ALBUM_THUMB" <<'PY'
import json,sys
p=sys.argv[1]; d=json.load(open(p))
d.update(root_path=sys.argv[2], album_levels=sys.argv[3], cron=sys.argv[4],
         run_immediately=sys.argv[5], album_thumb=sys.argv[6])
json.dump(d,open(p,"w"))
PY
fi

if $ENABLE_PET; then
  say
  say "${BOLD}Pet Tagger${RESET}"
  read -rp "Pet Tagger webpoort [2287]: " PET_PORT
  PET_PORT="${PET_PORT:-2287}"
  python3 - "$CFG" "$PET_PORT" <<'PY'
import json,sys
p=sys.argv[1]; d=json.load(open(p)); d["pet_port"]=int(sys.argv[2]); json.dump(d,open(p,"w"))
PY
fi

IMMICH_NETWORK=""
POSTGRES_CONTAINER=""
DB_HOST=""
DB_PORT="5432"
DB_USER=""
DB_PASS=""
DB_NAME=""

if $ENABLE_POWER; then
  say
  say "${BOLD}Immich Power Tools (advanced)${RESET}"
  read -rp "Power Tools webpoort [8001]: " POWER_PORT
  POWER_PORT="${POWER_PORT:-8001}"

  say "Ik probeer de TrueNAS Immich PostgreSQL-container automatisch te vinden..."
  POSTGRES_CONTAINER="$($SUDO docker ps --format '{{.Names}}' | grep -E '^ix-immich-.*(postgres|database|db).*$' | head -1 || true)"

  if [[ -n "$POSTGRES_CONTAINER" ]]; then
    IMMICH_NETWORK="$($SUDO docker inspect "$POSTGRES_CONTAINER" --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{"\n"}}{{end}}' | head -1)"
    # Read standard Postgres envs without echoing the password.
    ENV_DUMP="$($SUDO docker inspect "$POSTGRES_CONTAINER" --format '{{range .Config.Env}}{{println .}}{{end}}')"
    DB_USER="$(printf '%s\n' "$ENV_DUMP" | sed -n 's/^POSTGRES_USER=//p' | head -1)"
    DB_PASS="$(printf '%s\n' "$ENV_DUMP" | sed -n 's/^POSTGRES_PASSWORD=//p' | head -1)"
    DB_NAME="$(printf '%s\n' "$ENV_DUMP" | sed -n 's/^POSTGRES_DB=//p' | head -1)"
    DB_HOST="$POSTGRES_CONTAINER"
    ok "PostgreSQL gevonden: ${POSTGRES_CONTAINER}"
    [[ -n "$IMMICH_NETWORK" ]] && ok "Immich Docker-netwerk gevonden: ${IMMICH_NETWORK}"
  else
    warn "PostgreSQL-container niet automatisch gevonden."
  fi

  read -rp "DB host [${DB_HOST:-immich-postgres}]: " in; DB_HOST="${in:-${DB_HOST:-immich-postgres}}"
  read -rp "DB port [5432]: " in; DB_PORT="${in:-5432}"
  read -rp "DB gebruiker [${DB_USER:-postgres}]: " in; DB_USER="${in:-${DB_USER:-postgres}}"
  if [[ -z "$DB_PASS" ]]; then
    read -rsp "DB wachtwoord: " DB_PASS; say
  else
    say "DB wachtwoord: automatisch gevonden (wordt niet getoond)"
  fi
  read -rp "DB naam [${DB_NAME:-immich}]: " in; DB_NAME="${in:-${DB_NAME:-immich}}"

  python3 - "$CFG" "$POWER_PORT" "$DB_HOST" "$DB_PORT" "$DB_USER" "$DB_PASS" "$DB_NAME" "$IMMICH_NETWORK" <<'PY'
import json,sys
p=sys.argv[1]; d=json.load(open(p))
d.update(power_port=int(sys.argv[2]), db_host=sys.argv[3], db_port=sys.argv[4],
         db_user=sys.argv[5], db_pass=sys.argv[6], db_name=sys.argv[7],
         immich_network=sys.argv[8])
json.dump(d,open(p,"w"))
PY
fi

# Build Compose as JSON (valid YAML) to avoid quoting mistakes.
python3 - "$CFG" "$PAYLOAD" <<'PY'
import json, sys
cfg=json.load(open(sys.argv[1]))
services={}
volumes={}
networks={}

common_extra_hosts=["host.docker.internal:host-gateway"]

if cfg["enable_folder"]:
    env={
      "TZ":"Europe/Amsterdam",
      "API_URL":cfg["immich_api"],
      "API_KEY":cfg["api_key"],
      "ROOT_PATH":cfg["root_path"],
      "ALBUM_LEVELS":cfg["album_levels"],
      "CRON_EXPRESSION":cfg["cron"],
      "RUN_IMMEDIATELY":cfg["run_immediately"],
      "UNATTENDED":"1",
      "MODE":"CREATE",
      "SYNC_MODE":"0",
      "LOG_LEVEL":"INFO",
    }
    if cfg.get("album_thumb"): env["SET_ALBUM_THUMBNAIL"]=cfg["album_thumb"]
    services["folderalbums"]={
      "image":cfg["folder_image"],
      "restart":"unless-stopped",
      "extra_hosts":common_extra_hosts,
      "environment":env,
    }

if cfg["enable_pet"]:
    services["pettagger"]={
      "image":cfg["pet_image"],
      "restart":"unless-stopped",
      "extra_hosts":common_extra_hosts,
      "environment":{
        "IMMICH_URL":cfg["immich_base"],
        "IMMICH_API_KEY":cfg["api_key"],
        "IMMICH_EXTERNAL_URL":cfg["external_immich"],
      },
      "ports":[f'{cfg["pet_port"]}:8000'],
      "volumes":["pettagger_data:/data"],
    }
    volumes["pettagger_data"]={}

if cfg["enable_power"]:
    svc={
      "image":cfg["power_image"],
      "restart":"unless-stopped",
      "extra_hosts":common_extra_hosts,
      "environment":{
        "IMMICH_URL":cfg["immich_base"],
        "IMMICH_API_KEY":cfg["api_key"],
        "EXTERNAL_IMMICH_URL":cfg["external_immich"],
        "DB_HOST":cfg["db_host"],
        "DB_PORT":cfg["db_port"],
        "DB_USERNAME":cfg["db_user"],
        "DB_PASSWORD":cfg["db_pass"],
        "DB_DATABASE_NAME":cfg["db_name"],
      },
      "ports":[f'{cfg["power_port"]}:3000'],
      "volumes":["powertools_data:/app/data"],
    }
    if cfg.get("immich_network"):
        svc["networks"]=["default","immich_external"]
        networks["immich_external"]={"external":True,"name":cfg["immich_network"]}
    services["powertools"]=svc
    volumes["powertools_data"]={}

compose={"services":services}
if volumes: compose["volumes"]=volumes
if networks: compose["networks"]=networks

payload={
  "app_name":cfg["app_name"],
  "custom_app":True,
  "custom_compose_config_string":json.dumps(compose,indent=2),
}
json.dump(payload,open(sys.argv[2],"w"))
PY

say
say "${BOLD}Samenvatting${RESET}"
$ENABLE_FOLDER && say "  ✓ Folder → Album Sync"
$ENABLE_PET && say "  ✓ Pet Tagger"
$ENABLE_POWER && say "  ✓ Immich Power Tools (advanced)"
say "  Appnaam: ${APP_NAME}"
say "  Immich:  ${IMMICH_BASE_URL}"
say
ask_yes_no "Nu installeren als één TrueNAS App?" Y || exit 0

say
say "TrueNAS app wordt aangemaakt..."
$SUDO midclt call -j app.create "$(cat "$PAYLOAD")"
say
ok "Immich Toolbox is geïnstalleerd."

say
say "${BOLD}Open nu TrueNAS → Apps → Installed Applications → ${APP_NAME}${RESET}"
$ENABLE_PET && say "Pet Tagger UI:    http://${HOST_NAME}:${PET_PORT}"
$ENABLE_POWER && say "Power Tools UI:   http://${HOST_NAME}:${POWER_PORT}"
$ENABLE_FOLDER && say "Folder Albums:    bekijk containerlogs 'folderalbums'"
say
say "Veilige Folder Albums defaults: MODE=CREATE, SYNC_MODE=0 (geen cleanup/delete)."
