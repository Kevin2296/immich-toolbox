#!/usr/bin/env bash
set -Eeuo pipefail

APP_NAME="immichtoolbox"
TOOLBOX_VERSION="0.2.4"

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
for c in midclt python3 docker curl ss; do command -v "$c" >/dev/null 2>&1 || die "$c is missing."; done
[[ $EUID -eq 0 ]] && SUDO="" || SUDO="sudo"
$SUDO -v

yesno(){
  local p="$1" d="${2:-Y}" a
  if [[ "$d" == "Y" ]]; then read -rp "$p [Y/n]: " a; a="${a:-Y}"
  else read -rp "$p [y/N]: " a; a="${a:-N}"; fi
  [[ "$a" =~ ^[YyJj]$ ]]
}

port_busy(){
  local p="$1"
  ss -ltnH 2>/dev/null | awk '{print $4}' | grep -Eq "(^|:)$p$"
}

choose_port(){
  local label="$1" preferred="$2" p="$2"
  if port_busy "$preferred"; then
    warn "$label port $preferred is already in use."
    local candidate=$((preferred+1))
    while port_busy "$candidate" && ((candidate < preferred+100)); do candidate=$((candidate+1)); done
    read -rp "$label port [$candidate]: " p
    p="${p:-$candidate}"
  else
    read -rp "$label port [$preferred]: " p
    p="${p:-$preferred}"
  fi
  [[ "$p" =~ ^[0-9]+$ ]] || die "Invalid port: $p"
  port_busy "$p" && die "Port $p is already in use. Choose another port."
  printf '%s' "$p"
}

clear || true
say "${BOLD}Immich Toolbox ${TOOLBOX_VERSION}${RESET}"
say "============================================================"
say "Choose language / Kies taal / Sprache wählen"
say "  [1] English"
say "  [2] Nederlands"
say "  [3] Deutsch"
read -rp "Choice / Keuze / Auswahl [1]: " LC
case "${LC:-1}" in 2) LANG_CODE=nl;; 3) LANG_CODE=de;; *) LANG_CODE=en;; esac

say
case "$LANG_CODE" in
  nl) say "Eén TrueNAS App met optionele Immich-uitbreidingen.";;
  de) say "Eine TrueNAS App mit optionalen Immich-Erweiterungen.";;
  *) say "One TrueNAS App with optional Immich companion tools.";;
esac
say
say "  ${CYAN}[1]${RESET} Folder → Album Sync"
say "  ${CYAN}[2]${RESET} Pet Tagger"
say "  ${CYAN}[3]${RESET} Immich Power Tools"
case "$LANG_CODE" in
  nl) say "  ${GREEN}✓${RESET} Toolbox Dashboard     (automatisch inbegrepen)";;
  de) say "  ${GREEN}✓${RESET} Toolbox Dashboard     (automatisch enthalten)";;
  *)  say "  ${GREEN}✓${RESET} Toolbox Dashboard     (always included)";;
esac
say

ENABLE_FOLDER=false; ENABLE_PET=false; ENABLE_POWER=false
case "$LANG_CODE" in
  nl)
    yesno "Map → Album Sync inschakelen?" Y && ENABLE_FOLDER=true || true
    yesno "Pet Tagger inschakelen?" Y && ENABLE_PET=true || true
    yesno "Immich Power Tools inschakelen? (geavanceerd; database-toegang nodig)" N && ENABLE_POWER=true || true
    ;;
  de)
    yesno "Ordner → Album Sync aktivieren?" Y && ENABLE_FOLDER=true || true
    yesno "Pet Tagger aktivieren?" Y && ENABLE_PET=true || true
    yesno "Immich Power Tools aktivieren? (erweitert; Datenbankzugriff nötig)" N && ENABLE_POWER=true || true
    ;;
  *)
    yesno "Enable Folder → Album Sync?" Y && ENABLE_FOLDER=true || true
    yesno "Enable Pet Tagger?" Y && ENABLE_PET=true || true
    yesno "Enable Immich Power Tools? (advanced; database access required)" N && ENABLE_POWER=true || true
    ;;
esac

EXISTING="$($SUDO midclt call app.query 2>/dev/null || echo '[]')"
if python3 - "$EXISTING" <<'PY'
import json,sys
try:r=json.loads(sys.argv[1])
except Exception:r=[]
raise SystemExit(0 if any((x.get("id")=="immichtoolbox" or x.get("name")=="immichtoolbox") for x in r if isinstance(x,dict)) else 1)
PY
then
  die "immichtoolbox already exists. Stop/remove it first; this installer will not overwrite it."
fi

IMMICH_CONTAINER="$($SUDO docker ps --format '{{.Names}}' | grep -E '^ix-immich-server-1$|immich.*server' | head -1 || true)"
DETECTED_PORT=""
if [[ -n "$IMMICH_CONTAINER" ]]; then
  DETECTED_PORT="$($SUDO docker port "$IMMICH_CONTAINER" 2283/tcp 2>/dev/null | head -1 | sed -E 's/.*:([0-9]+)$/\1/' || true)"
fi
[[ "$DETECTED_PORT" =~ ^[0-9]+$ ]] || DETECTED_PORT="30041"
DETECTED_IP="$(hostname -I 2>/dev/null | tr ' ' '\n' | grep -E '^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.)' | head -1 || true)"
DEFAULT_URL=""
[[ -n "$DETECTED_IP" ]] && DEFAULT_URL="http://${DETECTED_IP}:${DETECTED_PORT}"

say
if [[ -n "$DEFAULT_URL" ]]; then
  case "$LANG_CODE" in nl) ok "Gedetecteerde Immich URL: $DEFAULT_URL";; de) ok "Erkannte Immich-URL: $DEFAULT_URL";; *) ok "Detected Immich URL: $DEFAULT_URL";; esac
fi
case "$LANG_CODE" in
  nl) read -rp "Immich URL die je in je browser gebruikt${DEFAULT_URL:+ [$DEFAULT_URL]}: " BROWSER_URL;;
  de) read -rp "Immich-URL, die du im Browser verwendest${DEFAULT_URL:+ [$DEFAULT_URL]}: " BROWSER_URL;;
  *)  read -rp "Immich URL you use in your browser${DEFAULT_URL:+ [$DEFAULT_URL]}: " BROWSER_URL;;
esac
BROWSER_URL="${BROWSER_URL:-$DEFAULT_URL}"; BROWSER_URL="${BROWSER_URL%/}"
[[ -n "$BROWSER_URL" ]] || die "Immich URL is required."

if curl -fsS --max-time 7 "${BROWSER_URL}/api/server/ping" >/dev/null 2>&1; then
  ok "Immich API: ${BROWSER_URL}/api"
else
  warn "Could not verify ${BROWSER_URL}/api/server/ping"
  yesno "Continue anyway?" N || exit 1
fi

API_SETTINGS_URL="${BROWSER_URL}/user-settings?isOpen=api-keys"
say
case "$LANG_CODE" in
 nl) say "${BOLD}Open deze pagina om de API-key aan te maken:${RESET}";;
 de) say "${BOLD}Öffne diese Seite, um den API-Schlüssel zu erstellen:${RESET}";;
 *) say "${BOLD}Open this page to create the API key:${RESET}";;
esac
say "  ${CYAN}${API_SETTINGS_URL}${RESET}"

if [[ -n "$IMMICH_CONTAINER" ]]; then INTERNAL_BASE="http://host.docker.internal:${DETECTED_PORT}"; else INTERNAL_BASE="$BROWSER_URL"; fi
say
case "$LANG_CODE" in nl) say "Interne container-URL: $INTERNAL_BASE";; de) say "Interne Container-URL: $INTERNAL_BASE";; *) say "Internal container URL: $INTERNAL_BASE";; esac
yesno "Advanced: override internal URL?" N && { read -rp "Internal URL [$INTERNAL_BASE]: " X; INTERNAL_BASE="${X:-$INTERNAL_BASE}"; INTERNAL_BASE="${INTERNAL_BASE%/}"; } || true
INTERNAL_API="${INTERNAL_BASE}/api"

show_permissions(){
  say
  say "${BOLD}Immich API key${RESET}"
  case "$LANG_CODE" in
    nl) say "Maak ÉÉN API-key aan met de naam 'Immich Toolbox'. Dezelfde key wordt door alle geselecteerde modules gebruikt.";;
    de) say "Erstelle EINEN API-Schlüssel namens 'Immich Toolbox'. Derselbe Schlüssel wird von allen gewählten Modulen verwendet.";;
    *) say "Create ONE API key named 'Immich Toolbox'. The same key is used by all selected modules.";;
  esac
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
    case "$LANG_CODE" in
      nl) say "  ${YELLOW}Power Tools vereist brede toegang: klik in Immich op 'Select all'. Je hoeft GEEN extra key aan te maken.${RESET}";;
      de) say "  ${YELLOW}Power Tools benötigt breite Rechte: in Immich 'Select all' wählen. KEIN zusätzlicher Schlüssel nötig.${RESET}";;
      *) say "  ${YELLOW}Power Tools needs broad access: choose 'Select all' in Immich. You do NOT need another key.${RESET}";;
    esac
    say
  fi
  say "$API_SETTINGS_URL"
  return 0
}
show_permissions
while true; do
  case "$LANG_CODE" in
    nl) say "[Enter] één API-key is aangemaakt    [V] Rechten opnieuw tonen    [Q] Stoppen";;
    de) say "[Enter] ein API-Schlüssel ist erstellt    [V] Rechte erneut anzeigen    [Q] Beenden";;
    *) say "[Enter] one API key is created    [V] Show permissions again    [Q] Quit";;
  esac
  read -rp "> " ACTION
  case "${ACTION:-}" in [Vv]) show_permissions;; [Qq]) exit 0;; "") break;; esac
done

read -rsp "API key: " API_KEY; say
[[ -n "$API_KEY" ]] || die "API key cannot be empty."

if curl -fsS --max-time 7 -H "x-api-key: $API_KEY" "${BROWSER_URL}/api/users/me" >/dev/null 2>&1; then
  ok "API key accepted by Immich."
else
  warn "The API key could not be validated via /api/users/me."
  yesno "Continue anyway?" N || exit 1
fi

DASHBOARD_PORT="$(choose_port "Toolbox Dashboard" 30042)"
say
ok "Dashboard port available: $DASHBOARD_PORT"

CFG="$(mktemp)"; PAYLOAD="$(mktemp)"
trap 'rm -f "$CFG" "$PAYLOAD"' EXIT
python3 - "$CFG" "$API_KEY" "$BROWSER_URL" "$INTERNAL_BASE" "$INTERNAL_API" "$ENABLE_FOLDER" "$ENABLE_PET" "$ENABLE_POWER" "$DASHBOARD_PORT" "$DETECTED_IP" <<'PY'
import json,sys
json.dump({"api":sys.argv[2],"browser":sys.argv[3],"internal":sys.argv[4],"internal_api":sys.argv[5],
"folder":sys.argv[6]=="true","pet":sys.argv[7]=="true","power":sys.argv[8]=="true","dashboard_port":int(sys.argv[9]),"host_ip":sys.argv[10]},open(sys.argv[1],"w"))
PY

if $ENABLE_FOLDER; then
  say
  LIB_JSON="$(curl -fsS --max-time 10 -H "x-api-key: $API_KEY" "${BROWSER_URL}/api/libraries" 2>/dev/null || true)"
  DETECTED_ROOT=""
  LIB_LINES=()
  if [[ -n "$LIB_JSON" ]]; then
    mapfile -t LIB_LINES < <(python3 - "$LIB_JSON" <<'PY'
import json,sys
try:d=json.loads(sys.argv[1])
except Exception:d=[]
if isinstance(d,dict): d=d.get("libraries", d.get("items", []))
for lib in d if isinstance(d,list) else []:
    if not isinstance(lib,dict): continue
    name=lib.get("name") or "External Library"
    paths=lib.get("importPaths") or lib.get("import_paths") or []
    for p in paths:
        if isinstance(p,str) and p: print(f"{name}\t{p}")
PY
)
  fi

  if ((${#LIB_LINES[@]} > 0)); then
    case "$LANG_CODE" in nl) say "${BOLD}External Libraries gevonden:${RESET}";; de) say "${BOLD}Externe Bibliotheken gefunden:${RESET}";; *) say "${BOLD}External Libraries found:${RESET}";; esac
    i=1
    for row in "${LIB_LINES[@]}"; do
      name="${row%%$'\t'*}"; path="${row#*$'\t'}"
      printf '  [%d] %s\n      %s\n' "$i" "$name" "$path"
      ((i++))
    done
    read -rp "Choose import path [1]: " LI
    LI="${LI:-1}"
    if [[ "$LI" =~ ^[0-9]+$ ]] && ((LI>=1 && LI<=${#LIB_LINES[@]})); then
      row="${LIB_LINES[$((LI-1))]}"; DETECTED_ROOT="${row#*$'\t'}"
      ok "Selected External Library root: $DETECTED_ROOT"
    fi
  else
    warn "External Library paths could not be detected automatically."
  fi

  read -rp "External Library root${DETECTED_ROOT:+ [$DETECTED_ROOT]}: " ROOT
  ROOT="${ROOT:-$DETECTED_ROOT}"
  [[ -n "$ROOT" ]] || { read -rp "External Library root (example /mnt/photos): " ROOT; }
  [[ -n "$ROOT" ]] || die "External Library root is required."

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
  say
  PET_PORT="$(choose_port "Pet Tagger" 2287)"
  ok "Pet Tagger port available: $PET_PORT"
  python3 - "$CFG" "$PET_PORT" <<'PY'
import json,sys;p=sys.argv[1];d=json.load(open(p));d["pet_port"]=int(sys.argv[2]);json.dump(d,open(p,"w"))
PY
fi

DB_NET=""; DB_CONT=""; DB_HOST=""; DB_USER=""; DB_PASS=""; DB_NAME=""; DB_PORT="5432"
if $ENABLE_POWER; then
  say
  POWER_PORT="$(choose_port "Power Tools" 8001)"
  ok "Power Tools port available: $POWER_PORT"
  DB_CONT="$($SUDO docker ps --format '{{.Names}}' | grep -E '^ix-immich-.*(postgres|pgvecto|database|db).*$' | head -1 || true)"
  if [[ -n "$DB_CONT" ]]; then
    DB_NET="$($SUDO docker inspect "$DB_CONT" --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{"\n"}}{{end}}' | head -1)"
    ENV_DUMP="$($SUDO docker inspect "$DB_CONT" --format '{{range .Config.Env}}{{println .}}{{end}}')"
    DB_USER="$(sed -n 's/^POSTGRES_USER=//p' <<<"$ENV_DUMP" | head -1)"
    DB_PASS="$(sed -n 's/^POSTGRES_PASSWORD=//p' <<<"$ENV_DUMP" | head -1)"
    DB_NAME="$(sed -n 's/^POSTGRES_DB=//p' <<<"$ENV_DUMP" | head -1)"
    DB_HOST="$DB_CONT"; ok "PostgreSQL detected: $DB_CONT"
  else
    warn "Immich PostgreSQL container was not detected automatically."
  fi
  read -rp "DB host [${DB_HOST:-immich-postgres}]: " X; DB_HOST="${X:-${DB_HOST:-immich-postgres}}"
  read -rp "DB port [5432]: " X; DB_PORT="${X:-5432}"
  read -rp "DB user [${DB_USER:-postgres}]: " X; DB_USER="${X:-${DB_USER:-postgres}}"
  if [[ -z "$DB_PASS" ]]; then read -rsp "DB password: " DB_PASS; say; else ok "DB password detected (hidden)."; fi
  read -rp "DB name [${DB_NAME:-immich}]: " X; DB_NAME="${X:-${DB_NAME:-immich}}"
  python3 - "$CFG" "$POWER_PORT" "$DB_HOST" "$DB_PORT" "$DB_USER" "$DB_PASS" "$DB_NAME" "$DB_NET" <<'PY'
import json,sys;p=sys.argv[1];d=json.load(open(p));d.update(power_port=int(sys.argv[2]),db_host=sys.argv[3],db_port=sys.argv[4],db_user=sys.argv[5],db_pass=sys.argv[6],db_name=sys.argv[7],db_net=sys.argv[8]);json.dump(d,open(p,"w"))
PY
fi

python3 - "$CFG" "$PAYLOAD" "$FOLDER_IMAGE" "$PET_IMAGE" "$POWER_IMAGE" "$DASHBOARD_IMAGE" <<'PY'
import json,sys,base64,html
c=json.load(open(sys.argv[1])); s={}; v={}; n={}; eh=["host.docker.internal:host-gateway"]
host=c.get("host_ip") or "127.0.0.1"
cards=[("Immich",c["browser"],"Open Immich"),("API Keys",c["browser"]+"/user-settings?isOpen=api-keys","Manage API keys")]
if c["folder"]: cards.append(("Folder → Album Sync","#","Background service • "+c.get("root","")))
if c["pet"]: cards.append(("Pet Tagger",f"http://{host}:{c['pet_port']}","Open Pet Tagger"))
if c["power"]: cards.append(("Immich Power Tools",f"http://{host}:{c['power_port']}","Open Power Tools"))
card_html="".join(f'<a class="card" href="{html.escape(url)}"><h2>{html.escape(name)}</h2><p>{html.escape(desc)}</p></a>' for name,url,desc in cards)
page=f'''<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Immich Toolbox</title><style>body{{font-family:system-ui;background:#111827;color:#f9fafb;margin:0}}main{{max-width:1000px;margin:auto;padding:40px 20px}}h1{{font-size:34px}}.grid{{display:grid;grid-template-columns:repeat(auto-fit,minmax(240px,1fr));gap:16px}}.card{{display:block;background:#1f2937;border:1px solid #374151;border-radius:16px;padding:22px;color:inherit;text-decoration:none}}.card:hover{{background:#273449}}p{{color:#cbd5e1}}.badge{{color:#86efac}}</style></head><body><main><h1>Immich Toolbox</h1><p class="badge">One app • optional companion tools</p><div class="grid">{card_html}</div></main></body></html>'''
encoded=base64.b64encode(page.encode()).decode()
s["dashboard"]={"image":sys.argv[6],"restart":"unless-stopped","ports":[f"{c['dashboard_port']}:80"],"command":["/bin/sh","-c",f"echo {encoded} | base64 -d > /usr/share/nginx/html/index.html && nginx -g 'daemon off;'"]}
if c["folder"]:
    e={"TZ":"Europe/Amsterdam","API_URL":c["internal_api"],"API_KEY":c["api"],"ROOT_PATH":c["root"],"ALBUM_LEVELS":c["level"],"CRON_EXPRESSION":c["cron"],"RUN_IMMEDIATELY":c["run"],"UNATTENDED":"1","MODE":"CREATE","SYNC_MODE":"0","LOG_LEVEL":"INFO"}
    if c.get("thumb"): e["SET_ALBUM_THUMBNAIL"]=c["thumb"]
    s["folderalbums"]={"image":sys.argv[3],"restart":"unless-stopped","extra_hosts":eh,"environment":e}
if c["pet"]:
    s["pettagger"]={"image":sys.argv[4],"restart":"unless-stopped","extra_hosts":eh,"environment":{"IMMICH_URL":c["internal"],"IMMICH_API_KEY":c["api"],"IMMICH_EXTERNAL_URL":c["browser"],"POLL_INTERVAL":"3600","GPU_WORKERS":"1"},"ports":[f"{c['pet_port']}:8000"],"volumes":["pettagger_data:/data"]}; v["pettagger_data"]={}
if c["power"]:
    x={"image":sys.argv[5],"restart":"unless-stopped","extra_hosts":eh,"environment":{"IMMICH_URL":c["internal"],"IMMICH_API_KEY":c["api"],"EXTERNAL_IMMICH_URL":c["browser"],"DB_HOST":c["db_host"],"DB_PORT":c["db_port"],"DB_USERNAME":c["db_user"],"DB_PASSWORD":c["db_pass"],"DB_DATABASE_NAME":c["db_name"]},"ports":[f"{c['power_port']}:3000"],"volumes":["powertools_data:/app/data"]}
    if c.get("db_net"): x["networks"]=["default","immich_external"]; n["immich_external"]={"external":True,"name":c["db_net"]}
    s["powertools"]=x; v["powertools_data"]={}
co={"services":s}
if v: co["volumes"]=v
if n: co["networks"]=n
json.dump({"app_name":"immichtoolbox","custom_app":True,"custom_compose_config_string":json.dumps(co,indent=2)},open(sys.argv[2],"w"))
PY

say
say "${BOLD}Summary / Samenvatting / Zusammenfassung${RESET}"
say "  Immich:    $BROWSER_URL"
say "  Internal:  $INTERNAL_BASE"
say "  Dashboard: port $DASHBOARD_PORT"
$ENABLE_FOLDER && say "  ✓ Folder → Album Sync"
$ENABLE_PET && say "  ✓ Pet Tagger (port $PET_PORT)"
$ENABLE_POWER && say "  ✓ Power Tools (port $POWER_PORT)"
say
yesno "Install now as one TrueNAS App?" Y || exit 0

$SUDO midclt call -j app.create "$(cat "$PAYLOAD")"
say
ok "Immich Toolbox installed."
if [[ -n "$DETECTED_IP" ]]; then
  say "Dashboard: http://${DETECTED_IP}:${DASHBOARD_PORT}"
  $ENABLE_PET && say "Pet Tagger: http://${DETECTED_IP}:${PET_PORT}"
  $ENABLE_POWER && say "Power Tools: http://${DETECTED_IP}:${POWER_PORT}"
fi
