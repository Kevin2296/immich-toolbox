#!/usr/bin/env bash
set -Eeuo pipefail

APP_NAME="immichtoolbox"
TOOLBOX_VERSION="0.2.3"
FOLDER_IMAGE="salvoxia/immich-folder-album-creator:1.0.0"
PET_IMAGE="ghcr.io/tedornitier/immich-pet-tagger:cpu"
POWER_IMAGE="ghcr.io/immich-power-tools/immich-power-tools:v0.22.0"
DASHBOARD_IMAGE="nginx:alpine"

BOLD=$'\033[1m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RED=$'\033[31m'; CYAN=$'\033[36m'; RESET=$'\033[0m'
say(){ printf '%s\n' "$*"; }
ok(){ printf '%s✓%s %s\n' "$GREEN" "$RESET" "$*"; }
warn(){ printf '%s!%s %s\n' "$YELLOW" "$RESET" "$*"; }
die(){ printf '%s✗%s %s\n' "$RED" "$RESET" "$*" >&2; exit 1; }

[[ -r /dev/tty ]] && exec </dev/tty
for c in midclt python3 docker curl; do command -v "$c" >/dev/null 2>&1 || die "$c is missing."; done
[[ $EUID -eq 0 ]] && SUDO="" || SUDO="sudo"
$SUDO -v

clear || true
say "${BOLD}Immich Toolbox ${TOOLBOX_VERSION}${RESET}"
say "============================================================"
say "Choose language / Kies taal / Sprache wählen"
say "  [1] English"
say "  [2] Nederlands"
say "  [3] Deutsch"
read -rp "Choice / Keuze / Auswahl [1]: " LC
case "${LC:-1}" in 2) LANG_CODE=nl;; 3) LANG_CODE=de;; *) LANG_CODE=en;; esac

tr(){
  case "${LANG_CODE}:$1" in
    en:title) echo "One TrueNAS App with optional Immich companion tools.";;
    nl:title) echo "Eén TrueNAS App met optionele Immich-uitbreidingen.";;
    de:title) echo "Eine TrueNAS App mit optionalen Immich-Erweiterungen.";;
    en:folderq) echo "Enable Folder → Album Sync?";;
    nl:folderq) echo "Map → Album Sync inschakelen?";;
    de:folderq) echo "Ordner → Album Sync aktivieren?";;
    en:petq) echo "Enable Pet Tagger?";;
    nl:petq) echo "Pet Tagger inschakelen?";;
    de:petq) echo "Pet Tagger aktivieren?";;
    en:powerq) echo "Enable Immich Power Tools? (advanced; DB access required)";;
    nl:powerq) echo "Immich Power Tools inschakelen? (geavanceerd; database-toegang nodig)";;
    de:powerq) echo "Immich Power Tools aktivieren? (erweitert; DB-Zugriff nötig)";;
    en:urlq) echo "Immich URL you use in your browser";;
    nl:urlq) echo "Immich URL die je in je browser gebruikt";;
    de:urlq) echo "Immich-URL, die du im Browser verwendest";;
    en:detected) echo "Detected Immich URL";;
    nl:detected) echo "Gedetecteerde Immich URL";;
    de:detected) echo "Erkannte Immich-URL";;
    en:apilink) echo "Open this page to create the API key";;
    nl:apilink) echo "Open deze pagina om de API-key aan te maken";;
    de:apilink) echo "Öffne diese Seite, um den API-Schlüssel zu erstellen";;
    en:internal) echo "Internal container URL";;
    nl:internal) echo "Interne container-URL";;
    de:internal) echo "Interne Container-URL";;
    en:advanced) echo "Advanced: override the internal URL?";;
    nl:advanced) echo "Geavanceerd: interne URL handmatig aanpassen?";;
    de:advanced) echo "Erweitert: interne URL manuell ändern?";;
    en:apiintro) echo "Create a dedicated API key named 'Immich Toolbox'.";;
    nl:apiintro) echo "Maak een aparte API-key aan met de naam 'Immich Toolbox'.";;
    de:apiintro) echo "Erstelle einen separaten API-Schlüssel mit dem Namen 'Immich Toolbox'.";;
    en:all) echo "Power Tools selected: choose Select all / ALL API permissions.";;
    nl:all) echo "Power Tools geselecteerd: kies Select all / ALLE API-permissies.";;
    de:all) echo "Power Tools ausgewählt: Select all / ALLE API-Berechtigungen wählen.";;
    en:menu) echo "[Enter] API key created    [V] Show permissions again    [Q] Quit";;
    nl:menu) echo "[Enter] API-key is aangemaakt    [V] Rechten opnieuw tonen    [Q] Stoppen";;
    de:menu) echo "[Enter] API-Schlüssel erstellt    [V] Rechte erneut anzeigen    [Q] Beenden";;
    en:dashboardport) echo "Toolbox dashboard port";;
    nl:dashboardport) echo "Toolbox dashboard-poort";;
    de:dashboardport) echo "Toolbox-Dashboard-Port";;
    en:summary) echo "Summary";;
    nl:summary) echo "Samenvatting";;
    de:summary) echo "Zusammenfassung";;
    en:installq) echo "Install now as one TrueNAS App?";;
    nl:installq) echo "Nu installeren als één TrueNAS App?";;
    de:installq) echo "Jetzt als eine TrueNAS App installieren?";;
    *) echo "$1";;
  esac
}

yesno(){
  local p="$1" d="${2:-Y}" a
  if [[ "$d" == Y ]]; then read -rp "$p [Y/n]: " a; a="${a:-Y}"
  else read -rp "$p [y/N]: " a; a="${a:-N}"; fi
  [[ "$a" =~ ^[YyJj]$ ]]
}

say "$(tr title)"
say
say "  ${CYAN}[1]${RESET} Folder → Album Sync"
say "  ${CYAN}[2]${RESET} Pet Tagger"
say "  ${CYAN}[3]${RESET} Immich Power Tools"
say "  ${CYAN}[4]${RESET} Toolbox Dashboard (always included)"
say

ENABLE_FOLDER=false; ENABLE_PET=false; ENABLE_POWER=false
yesno "$(tr folderq)" Y && ENABLE_FOLDER=true || true
yesno "$(tr petq)" Y && ENABLE_PET=true || true
yesno "$(tr powerq)" N && ENABLE_POWER=true || true

EXISTING="$($SUDO midclt call app.query 2>/dev/null || echo '[]')"
if python3 - "$EXISTING" <<'PY'
import json,sys
try:r=json.loads(sys.argv[1])
except Exception:r=[]
raise SystemExit(0 if any((x.get("id")=="immichtoolbox" or x.get("name")=="immichtoolbox") for x in r if isinstance(x,dict)) else 1)
PY
then
  die "immichtoolbox already exists. Stop/remove or upgrade it intentionally first."
fi

IMMICH_CONTAINER="$($SUDO docker ps --format '{{.Names}}' | grep -E '^ix-immich-(server|immich)-1$|^ix-immich-server-1$' | head -1 || true)"
[[ -z "$IMMICH_CONTAINER" ]] && IMMICH_CONTAINER="$($SUDO docker ps --format '{{.Names}}' | grep -E 'immich.*server' | head -1 || true)"
DETECTED_PORT=""
if [[ -n "$IMMICH_CONTAINER" ]]; then
  DETECTED_PORT="$($SUDO docker port "$IMMICH_CONTAINER" 2283/tcp 2>/dev/null | head -1 | sed -E 's/.*:([0-9]+)$/\1/' || true)"
fi
[[ "$DETECTED_PORT" =~ ^[0-9]+$ ]] || DETECTED_PORT="30041"

DETECTED_IP="$(hostname -I 2>/dev/null | tr ' ' '\n' | grep -E '^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.)' | head -1 || true)"
[[ -z "$DETECTED_IP" ]] && DETECTED_IP="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
DEFAULT_URL=""
[[ -n "$DETECTED_IP" ]] && DEFAULT_URL="http://${DETECTED_IP}:${DETECTED_PORT}"

say
[[ -n "$DEFAULT_URL" ]] && ok "$(tr detected): ${DEFAULT_URL}"
read -rp "$(tr urlq)${DEFAULT_URL:+ [$DEFAULT_URL]}: " BROWSER_URL
BROWSER_URL="${BROWSER_URL:-$DEFAULT_URL}"
[[ -n "$BROWSER_URL" ]] || die "Immich URL is required."
BROWSER_URL="${BROWSER_URL%/}"

if curl -fsS --max-time 7 "${BROWSER_URL}/api/server/ping" >/dev/null 2>&1; then
  ok "Immich API: ${BROWSER_URL}/api"
else
  warn "Could not verify ${BROWSER_URL}/api/server/ping"
  yesno "Continue anyway?" N || exit 1
fi

API_SETTINGS_URL="${BROWSER_URL}/user-settings?isOpen=api-keys"
say
say "${BOLD}$(tr apilink):${RESET}"
say "  ${CYAN}${API_SETTINGS_URL}${RESET}"
say

if [[ -n "$IMMICH_CONTAINER" ]]; then INTERNAL_BASE="http://host.docker.internal:${DETECTED_PORT}"
else INTERNAL_BASE="$BROWSER_URL"; fi
say "$(tr internal): ${INTERNAL_BASE}"
if yesno "$(tr advanced)" N; then
  read -rp "$(tr internal) [$INTERNAL_BASE]: " CUSTOM_INTERNAL
  INTERNAL_BASE="${CUSTOM_INTERNAL:-$INTERNAL_BASE}"
  INTERNAL_BASE="${INTERNAL_BASE%/}"
fi
INTERNAL_API="${INTERNAL_BASE}/api"

show_permissions(){
  say
  say "${BOLD}Immich API key${RESET}"
  say "$(tr apiintro)"
  say
  if $ENABLE_FOLDER; then
    say "${BOLD}Folder → Album Sync${RESET}"
    printf '  ✓ %s\n' asset.read album.read album.create album.update albumAsset.create
    say
  fi
  if $ENABLE_PET; then
    say "${BOLD}Pet Tagger${RESET}"
    printf '  ✓ %s\n' asset.read asset.view person.create person.read person.update person.delete person.reassign face.create face.read face.delete
    say "  ○ tag.create"; say "  ○ tag.asset"; say
  fi
  if $ENABLE_POWER; then
    say "${BOLD}Immich Power Tools${RESET}"
    say "  ${YELLOW}$(tr all)${RESET}"; say
  fi
  say "$(tr apilink):"
  say "  ${API_SETTINGS_URL}"
  return 0
}
show_permissions
while true; do
  say "$(tr menu)"
  read -rp "> " ACTION
  case "${ACTION:-}" in [Vv]) show_permissions;; [Qq]) exit 0;; "") break;; esac
done

read -rsp "API key: " API_KEY; say
[[ -n "$API_KEY" ]] || die "API key cannot be empty."
read -rp "$(tr dashboardport) [30042]: " DASHBOARD_PORT
DASHBOARD_PORT="${DASHBOARD_PORT:-30042}"

CFG="$(mktemp)"; PAYLOAD="$(mktemp)"
trap 'rm -f "$CFG" "$PAYLOAD"' EXIT
python3 - "$CFG" "$API_KEY" "$BROWSER_URL" "$INTERNAL_BASE" "$INTERNAL_API" "$ENABLE_FOLDER" "$ENABLE_PET" "$ENABLE_POWER" "$DASHBOARD_PORT" <<'PY'
import json,sys
json.dump({"api":sys.argv[2],"browser":sys.argv[3],"internal":sys.argv[4],"internal_api":sys.argv[5],
"folder":sys.argv[6]=="true","pet":sys.argv[7]=="true","power":sys.argv[8]=="true","dashboard_port":int(sys.argv[9])},open(sys.argv[1],"w"))
PY

if $ENABLE_FOLDER; then
  read -rp "External Library root [/external/fotos]: " ROOT; ROOT="${ROOT:-/external/fotos}"
  read -rp "Album level [1]: " LEVEL; LEVEL="${LEVEL:-1}"
  say "1) Daily 03:00  2) Every 6h  3) Hourly  4) Custom cron"
  read -rp "Choice [1]: " SC
  case "${SC:-1}" in 2) CRON='0 */6 * * *';; 3) CRON='0 * * * *';; 4) read -rp "Cron: " CRON;; *) CRON='0 3 * * *';; esac
  yesno "Run album sync immediately?" Y && RUN_NOW=true || RUN_NOW=false
  yesno "Random album thumbnail?" Y && THUMB=random || THUMB=""
  python3 - "$CFG" "$ROOT" "$LEVEL" "$CRON" "$RUN_NOW" "$THUMB" <<'PY'
import json,sys;p=sys.argv[1];d=json.load(open(p));d.update(root=sys.argv[2],level=sys.argv[3],cron=sys.argv[4],run=sys.argv[5],thumb=sys.argv[6]);json.dump(d,open(p,"w"))
PY
fi

if $ENABLE_PET; then
  read -rp "Pet Tagger web port [2287]: " PET_PORT; PET_PORT="${PET_PORT:-2287}"
  python3 - "$CFG" "$PET_PORT" <<'PY'
import json,sys;p=sys.argv[1];d=json.load(open(p));d["pet_port"]=int(sys.argv[2]);json.dump(d,open(p,"w"))
PY
fi

DB_NET=""; DB_CONT=""; DB_HOST=""; DB_USER=""; DB_PASS=""; DB_NAME=""; DB_PORT="5432"
if $ENABLE_POWER; then
  read -rp "Power Tools web port [8001]: " POWER_PORT; POWER_PORT="${POWER_PORT:-8001}"
  DB_CONT="$($SUDO docker ps --format '{{.Names}}' | grep -E '^ix-immich-.*(postgres|database|db).*$' | head -1 || true)"
  if [[ -n "$DB_CONT" ]]; then
    DB_NET="$($SUDO docker inspect "$DB_CONT" --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{"\n"}}{{end}}' | head -1)"
    ENV_DUMP="$($SUDO docker inspect "$DB_CONT" --format '{{range .Config.Env}}{{println .}}{{end}}')"
    DB_USER="$(sed -n 's/^POSTGRES_USER=//p' <<<"$ENV_DUMP" | head -1)"
    DB_PASS="$(sed -n 's/^POSTGRES_PASSWORD=//p' <<<"$ENV_DUMP" | head -1)"
    DB_NAME="$(sed -n 's/^POSTGRES_DB=//p' <<<"$ENV_DUMP" | head -1)"
    DB_HOST="$DB_CONT"; ok "PostgreSQL detected: $DB_CONT"
  fi
  read -rp "DB host [${DB_HOST:-immich-postgres}]: " X; DB_HOST="${X:-${DB_HOST:-immich-postgres}}"
  read -rp "DB port [5432]: " X; DB_PORT="${X:-5432}"
  read -rp "DB user [${DB_USER:-postgres}]: " X; DB_USER="${X:-${DB_USER:-postgres}}"
  if [[ -z "$DB_PASS" ]]; then read -rsp "DB password: " DB_PASS; say; fi
  read -rp "DB name [${DB_NAME:-immich}]: " X; DB_NAME="${X:-${DB_NAME:-immich}}"
  python3 - "$CFG" "$POWER_PORT" "$DB_HOST" "$DB_PORT" "$DB_USER" "$DB_PASS" "$DB_NAME" "$DB_NET" <<'PY'
import json,sys;p=sys.argv[1];d=json.load(open(p));d.update(power_port=int(sys.argv[2]),db_host=sys.argv[3],db_port=sys.argv[4],db_user=sys.argv[5],db_pass=sys.argv[6],db_name=sys.argv[7],db_net=sys.argv[8]);json.dump(d,open(p,"w"))
PY
fi

python3 - "$CFG" "$PAYLOAD" "$FOLDER_IMAGE" "$PET_IMAGE" "$POWER_IMAGE" "$DASHBOARD_IMAGE" <<'PY'
import json,sys,html
c=json.load(open(sys.argv[1])); services={}; volumes={}; networks={}; eh=["host.docker.internal:host-gateway"]
if c["folder"]:
    e={"TZ":"Europe/Amsterdam","API_URL":c["internal_api"],"API_KEY":c["api"],"ROOT_PATH":c["root"],"ALBUM_LEVELS":c["level"],"CRON_EXPRESSION":c["cron"],"RUN_IMMEDIATELY":c["run"],"UNATTENDED":"1","MODE":"CREATE","SYNC_MODE":"0","LOG_LEVEL":"INFO"}
    if c.get("thumb"): e["SET_ALBUM_THUMBNAIL"]=c["thumb"]
    services["folderalbums"]={"image":sys.argv[3],"restart":"unless-stopped","extra_hosts":eh,"environment":e}
if c["pet"]:
    services["pettagger"]={"image":sys.argv[4],"restart":"unless-stopped","extra_hosts":eh,"environment":{"IMMICH_URL":c["internal"],"IMMICH_API_KEY":c["api"],"IMMICH_EXTERNAL_URL":c["browser"],"POLL_INTERVAL":"3600","GPU_WORKERS":"1"},"ports":[f'{c["pet_port"]}:8000'],"volumes":["pettagger_data:/data"]}
    volumes["pettagger_data"]={}
if c["power"]:
    x={"image":sys.argv[5],"restart":"unless-stopped","extra_hosts":eh,"environment":{"IMMICH_URL":c["internal"],"IMMICH_API_KEY":c["api"],"EXTERNAL_IMMICH_URL":c["browser"],"DB_HOST":c["db_host"],"DB_PORT":c["db_port"],"DB_USERNAME":c["db_user"],"DB_PASSWORD":c["db_pass"],"DB_DATABASE_NAME":c["db_name"]},"ports":[f'{c["power_port"]}:3000'],"volumes":["powertools_data:/app/data"]}
    volumes["powertools_data"]={}
    if c.get("db_net"): x["networks"]=["default","immich_external"]; networks["immich_external"]={"external":True,"name":c["db_net"]}
    services["powertools"]=x

host=c["browser"].split("://",1)[-1].split("/",1)[0].split(":",1)[0]
scheme=c["browser"].split("://",1)[0]
cards=[f'<a class="card" href="{html.escape(c["browser"])}" target="_blank"><h2>Immich</h2><p>Open your Immich library</p></a>',
       f'<a class="card" href="{html.escape(c["browser"]+"/user-settings?isOpen=api-keys")}" target="_blank"><h2>API Keys</h2><p>Manage Immich Toolbox API access</p></a>']
if c["folder"]: cards.append(f'<a class="card" href="{html.escape(c["browser"]+"/albums")}" target="_blank"><h2>Folder → Albums</h2><p>Background sync. Open Immich albums.</p></a>')
if c["pet"]: cards.append(f'<a class="card" href="{scheme}://{host}:{c["pet_port"]}" target="_blank"><h2>Pet Tagger</h2><p>Pet recognition and tagging</p></a>')
if c["power"]: cards.append(f'<a class="card" href="{scheme}://{host}:{c["power_port"]}" target="_blank"><h2>Immich Power Tools</h2><p>Management, workflows and analytics</p></a>')
page="<!doctype html><html><head><meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'><title>Immich Toolbox</title><style>body{font-family:system-ui,sans-serif;background:#111827;color:#f9fafb;margin:0;padding:32px}.wrap{max-width:1000px;margin:auto}h1{font-size:32px}.sub{color:#9ca3af;margin-bottom:28px}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(240px,1fr));gap:18px}.card{display:block;padding:22px;border:1px solid #374151;border-radius:16px;background:#1f2937;color:#fff;text-decoration:none}.card:hover{background:#273449}.card h2{margin:0 0 8px}.card p{margin:0;color:#cbd5e1}.note{margin-top:28px;color:#9ca3af;font-size:14px}</style></head><body><div class='wrap'><h1>Immich Toolbox</h1><div class='sub'>One place for your optional Immich companion tools.</div><div class='grid'>"+"".join(cards)+"</div><div class='note'>Container-changing settings are still managed from TrueNAS/installer. This dashboard is a safe launcher.</div></div></body></html>"
services["dashboard"]={"image":sys.argv[6],"restart":"unless-stopped","ports":[f'{c["dashboard_port"]}:80'],"environment":{"DASHBOARD_HTML":page},"command":["/bin/sh","-c","printf '%s' \"$DASHBOARD_HTML\" > /usr/share/nginx/html/index.html && exec nginx -g 'daemon off;'"]}
compose={"services":services}
if volumes: compose["volumes"]=volumes
if networks: compose["networks"]=networks
json.dump({"app_name":"immichtoolbox","custom_app":True,"custom_compose_config_string":json.dumps(compose,indent=2)},open(sys.argv[2],"w"))
PY

say
say "${BOLD}$(tr summary)${RESET}"
say "  Browser URL:   $BROWSER_URL"
say "  Internal URL:  $INTERNAL_BASE"
say "  API settings:  $API_SETTINGS_URL"
say "  Dashboard port: $DASHBOARD_PORT"
$ENABLE_FOLDER && say "  ✓ Folder → Album Sync"
$ENABLE_PET && say "  ✓ Pet Tagger"
$ENABLE_POWER && say "  ✓ Immich Power Tools"
say
yesno "$(tr installq)" Y || exit 0
$SUDO midclt call -j app.create "$(cat "$PAYLOAD")"
say
ok "Immich Toolbox installed."
HOST_ONLY="${BROWSER_URL#*://}"; HOST_ONLY="${HOST_ONLY%%/*}"; HOST_ONLY="${HOST_ONLY%%:*}"
SCHEME="${BROWSER_URL%%://*}"
say "Dashboard: ${SCHEME}://${HOST_ONLY}:${DASHBOARD_PORT}"
