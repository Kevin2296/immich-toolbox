#!/usr/bin/env bash
set -Eeuo pipefail

APP_NAME="immichtoolbox"
TOOLBOX_VERSION="0.4.0"
FOLDER_IMAGE="salvoxia/immich-folder-album-creator:1.0.0"
PET_IMAGE="ghcr.io/tedornitier/immich-pet-tagger:cpu"
POWER_IMAGE="ghcr.io/immich-power-tools/immich-power-tools:v0.22.0"
DASHBOARD_IMAGE="nginx:alpine"
REPO_RAW="https://raw.githubusercontent.com/Kevin2296/immich-toolbox/main/install.sh"

BOLD=$'\033[1m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RED=$'\033[31m'; CYAN=$'\033[36m'; RESET=$'\033[0m'
say(){ printf '%s\n' "$*"; }
ok(){ printf '%s✓%s %s\n' "$GREEN" "$RESET" "$*"; }
warn(){ printf '%s!%s %s\n' "$YELLOW" "$RESET" "$*" >&2; }
die(){ printf '%s✗%s %s\n' "$RED" "$RESET" "$*" >&2; exit 1; }

[[ -r /dev/tty ]] && exec </dev/tty
for c in midclt python3 docker curl ss; do command -v "$c" >/dev/null 2>&1 || die "$c is missing."; done
[[ $EUID -eq 0 ]] && SUDO="" || SUDO="sudo"
$SUDO -v

yesno(){ local p="$1" d="${2:-Y}" a; if [[ "$d" == Y ]]; then read -rp "$p [Y/n]: " a; a="${a:-Y}"; else read -rp "$p [y/N]: " a; a="${a:-N}"; fi; [[ "$a" =~ ^[YyJj]$ ]]; }
port_busy(){ ss -ltnH 2>/dev/null | awk '{print $4}' | grep -Eq "(^|:)$1$"; }
container_for_service(){ $SUDO docker ps -a --filter "label=com.docker.compose.project=ix-${APP_NAME}" --filter "label=com.docker.compose.service=$1" --format '{{.Names}}' | head -1; }
published_port(){ local c; c="$(container_for_service "$1")"; [[ -n "$c" ]] || return 0; $SUDO docker port "$c" "$2/tcp" 2>/dev/null | head -1 | sed -E 's/.*:([0-9]+)$/\1/' || true; }
env_of(){ local c; c="$(container_for_service "$1")"; [[ -n "$c" ]] || return 0; $SUDO docker inspect "$c" --format '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null | sed -n "s/^$2=//p" | head -1; }
has_service(){ [[ -n "$(container_for_service "$1")" ]]; }
choose_port(){
  local label="$1" preferred="$2" allowed="${3:-}" p candidate
  if [[ -n "$allowed" && "$preferred" == "$allowed" ]]; then read -rp "$label port [$preferred]: " p; p="${p:-$preferred}"; [[ "$p" == "$allowed" ]] && { printf '%s' "$p"; return; }; fi
  if ! port_busy "$preferred"; then read -rp "$label port [$preferred]: " p; p="${p:-$preferred}"; else warn "$label port $preferred is already in use."; candidate=$((preferred+1)); while port_busy "$candidate"; do candidate=$((candidate+1)); done; read -rp "$label port [$candidate]: " p; p="${p:-$candidate}"; fi
  [[ "$p" =~ ^[0-9]+$ ]] || die "Invalid port: $p"
  [[ -n "$allowed" && "$p" == "$allowed" ]] || { port_busy "$p" && die "Port $p is already in use."; }
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

EXISTING_JSON="$($SUDO midclt call app.query 2>/dev/null || echo '[]')"
EXISTS=false
if python3 - "$EXISTING_JSON" <<'PY'
import json,sys
try:r=json.loads(sys.argv[1])
except Exception:r=[]
raise SystemExit(0 if any((x.get('id')=='immichtoolbox' or x.get('name')=='immichtoolbox') for x in r if isinstance(x,dict)) else 1)
PY
then EXISTS=true; fi

MODE=create
if $EXISTS; then
  say
  case "$LANG_CODE" in
    nl) warn "Er bestaat al een Immich Toolbox installatie."; say "  [1] Update uitvoeren (huidige configuratie + data behouden)"; say "  [2] Configuratie wijzigen / opnieuw instellen"; say "  [3] Immich Toolbox verwijderen"; say "  [4] Stoppen"; read -rp "Keuze [1]: " CH;;
    de) warn "Immich Toolbox ist bereits installiert."; say "  [1] Aktualisieren (Konfiguration + Daten behalten)"; say "  [2] Neu konfigurieren"; say "  [3] Immich Toolbox entfernen"; say "  [4] Beenden"; read -rp "Auswahl [1]: " CH;;
    *) warn "Immich Toolbox is already installed."; say "  [1] Update (preserve current configuration + data)"; say "  [2] Reconfigure"; say "  [3] Remove Immich Toolbox"; say "  [4] Quit"; read -rp "Choice [1]: " CH;;
  esac
  case "${CH:-1}" in
    1) MODE=update;;
    2) MODE=reconfigure;;
    3)
      say; say "${BOLD}Remove Immich Toolbox${RESET}"
      say "  [1] Remove app, keep TrueNAS-managed volumes/data"
      say "  [2] Remove app + TrueNAS-managed volumes/data"
      say "  [3] Cancel"
      read -rp "Choice [1]: " RM
      case "${RM:-1}" in
        1) yesno "Remove immichtoolbox but keep volumes/data?" N || exit 0; $SUDO midclt call -j app.delete "$APP_NAME" '{"remove_images":false,"remove_ix_volumes":false,"force_remove_ix_volumes":false,"force_remove_custom_app":false}'; ok "Immich Toolbox removed; TrueNAS-managed volumes were kept."; exit 0;;
        2) warn "This can permanently delete Toolbox-managed data."; yesno "Really remove app AND TrueNAS-managed volumes?" N || exit 0; $SUDO midclt call -j app.delete "$APP_NAME" '{"remove_images":false,"remove_ix_volumes":true,"force_remove_ix_volumes":false,"force_remove_custom_app":false}'; ok "Immich Toolbox and TrueNAS-managed volumes removed."; exit 0;;
        *) exit 0;;
      esac;;
    *) exit 0;;
  esac
fi

IMMICH_CONTAINER="$($SUDO docker ps --format '{{.Names}}' | grep -E '^ix-immich-server-1$|immich.*server' | head -1 || true)"
DETECTED_PORT=""; [[ -n "$IMMICH_CONTAINER" ]] && DETECTED_PORT="$($SUDO docker port "$IMMICH_CONTAINER" 2283/tcp 2>/dev/null | head -1 | sed -E 's/.*:([0-9]+)$/\1/' || true)"
[[ "$DETECTED_PORT" =~ ^[0-9]+$ ]] || DETECTED_PORT="30041"
DETECTED_IP="$(hostname -I 2>/dev/null | tr ' ' '\n' | grep -E '^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.)' | head -1 || true)"
[[ -n "$DETECTED_IP" ]] || DETECTED_IP="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
DEFAULT_URL=""; [[ -n "$DETECTED_IP" ]] && DEFAULT_URL="http://${DETECTED_IP}:${DETECTED_PORT}"
TIMEZONE="$(timedatectl show -p Timezone --value 2>/dev/null || true)"; [[ -n "$TIMEZONE" ]] || TIMEZONE="$(cat /etc/timezone 2>/dev/null || true)"; [[ -n "$TIMEZONE" ]] || TIMEZONE="UTC"

ENABLE_FOLDER=false; ENABLE_PET=false; ENABLE_POWER=false
API_KEY=""; BROWSER_URL=""; INTERNAL_BASE=""; DASHBOARD_PORT=""; PET_PORT=""; POWER_PORT=""
ROOT=""; LEVEL="1"; CRON='0 3 * * *'; SCHEDULE_LABEL='Daily at 03:00'; RUN_NOW="true"; THUMB="random"; DETECTED_LIB=""
DB_HOST=""; DB_PORT="5432"; DB_USER=""; DB_PASS=""; DB_NAME=""; DB_NET=""

if [[ "$MODE" == update ]]; then
  has_service folderalbums && ENABLE_FOLDER=true || true
  has_service pettagger && ENABLE_PET=true || true
  has_service powertools && ENABLE_POWER=true || true
  API_KEY="$(env_of folderalbums API_KEY)"; [[ -n "$API_KEY" ]] || API_KEY="$(env_of pettagger IMMICH_API_KEY)"; [[ -n "$API_KEY" ]] || API_KEY="$(env_of powertools IMMICH_API_KEY)"
  BROWSER_URL="$(env_of pettagger IMMICH_EXTERNAL_URL)"; [[ -n "$BROWSER_URL" ]] || BROWSER_URL="$(env_of powertools EXTERNAL_IMMICH_URL)"; [[ -n "$BROWSER_URL" ]] || BROWSER_URL="$DEFAULT_URL"
  INTERNAL_BASE="$(env_of pettagger IMMICH_URL)"; [[ -n "$INTERNAL_BASE" ]] || { X="$(env_of folderalbums API_URL)"; INTERNAL_BASE="${X%/api}"; }; [[ -n "$INTERNAL_BASE" ]] || INTERNAL_BASE="http://host.docker.internal:${DETECTED_PORT}"
  DASHBOARD_PORT="$(published_port dashboard 80)"; [[ -n "$DASHBOARD_PORT" ]] || DASHBOARD_PORT=30042
  if $ENABLE_FOLDER; then ROOT="$(env_of folderalbums ROOT_PATH)"; LEVEL="$(env_of folderalbums ALBUM_LEVELS)"; CRON="$(env_of folderalbums CRON_EXPRESSION)"; RUN_NOW="$(env_of folderalbums RUN_IMMEDIATELY)"; THUMB="$(env_of folderalbums SET_ALBUM_THUMBNAIL)"; [[ -n "$LEVEL" ]] || LEVEL=1; [[ -n "$CRON" ]] || CRON='0 3 * * *'; [[ "$CRON" == '0 3 * * *' ]] && SCHEDULE_LABEL='Daily at 03:00' || SCHEDULE_LABEL="$CRON"; fi
  if $ENABLE_PET; then PET_PORT="$(published_port pettagger 8000)"; [[ -n "$PET_PORT" ]] || PET_PORT=2287; fi
  if $ENABLE_POWER; then POWER_PORT="$(published_port powertools 3000)"; [[ -n "$POWER_PORT" ]] || POWER_PORT=8001; DB_HOST="$(env_of powertools DB_HOST)"; DB_PORT="$(env_of powertools DB_PORT)"; DB_USER="$(env_of powertools DB_USERNAME)"; DB_PASS="$(env_of powertools DB_PASSWORD)"; DB_NAME="$(env_of powertools DB_DATABASE_NAME)"; [[ -n "$DB_PORT" ]] || DB_PORT=5432; C="$(container_for_service powertools)"; [[ -n "$C" ]] && DB_NET="$($SUDO docker inspect "$C" --format '{{range $k,$v := .NetworkSettings.Networks}}{{if ne $k "ix-immichtoolbox_default"}}{{$k}}{{"\n"}}{{end}}{{end}}' 2>/dev/null | head -1 || true)"; fi
  [[ -n "$API_KEY" ]] || { warn "Existing API key could not be read; asking once."; read -rsp "API key: " API_KEY; say; }
  [[ -n "$ROOT" || "$ENABLE_FOLDER" == false ]] || { warn "Existing Folder Albums root could not be read."; read -rp "External Library root: " ROOT; }
  say; say "${BOLD}Existing configuration detected${RESET}"
  say "  Immich:       $BROWSER_URL"; say "  Internal:     $INTERNAL_BASE"; say "  Dashboard:    :$DASHBOARD_PORT"; say "  API key:      ✓ found (hidden)"
  $ENABLE_FOLDER && { say "  Folder Albums: enabled"; say "    Root:       $ROOT"; say "    Level:      $LEVEL"; say "    Schedule:   $CRON"; }
  $ENABLE_PET && say "  Pet Tagger:   enabled • :$PET_PORT"
  $ENABLE_POWER && say "  Power Tools:  enabled • :$POWER_PORT • DB $DB_HOST/$DB_NAME"
  say; yesno "Keep these settings and update only the Toolbox version/dashboard?" Y || { warn "Use option 2 (Reconfigure) instead."; exit 0; }
else
  say; case "$LANG_CODE" in nl) say "Eén TrueNAS App met optionele Immich-uitbreidingen.";; de) say "Eine TrueNAS App mit optionalen Immich-Erweiterungen.";; *) say "One TrueNAS App with optional Immich companion tools.";; esac
  say "  [1] Folder → Album Sync"; say "  [2] Pet Tagger"; say "  [3] Immich Power Tools"; say "  ✓ Toolbox Dashboard (always included)"; say
  yesno "Enable Folder → Album Sync?" Y && ENABLE_FOLDER=true || true
  yesno "Enable Pet Tagger?" Y && ENABLE_PET=true || true
  yesno "Enable Immich Power Tools?" N && ENABLE_POWER=true || true
  [[ -n "$DEFAULT_URL" ]] && ok "Detected Immich URL: $DEFAULT_URL"
  read -rp "Immich URL used in your browser${DEFAULT_URL:+ [$DEFAULT_URL]}: " BROWSER_URL; BROWSER_URL="${BROWSER_URL:-$DEFAULT_URL}"; BROWSER_URL="${BROWSER_URL%/}"; [[ -n "$BROWSER_URL" ]] || die "Immich URL required."
  INTERNAL_BASE="http://host.docker.internal:${DETECTED_PORT}"
  say "API key settings: ${BROWSER_URL}/user-settings?isOpen=api-keys"
  say "Create ONE API key named 'Immich Toolbox'. If Power Tools is enabled, choose Select all."
  read -rsp "API key: " API_KEY; say; [[ -n "$API_KEY" ]] || die "API key required."
  if curl -fsS --max-time 7 -H "x-api-key: $API_KEY" "${BROWSER_URL}/api/users/me" >/dev/null 2>&1; then ok "API key accepted by Immich."; else warn "API key validation failed."; yesno "Continue anyway?" N || exit 1; fi
  DASHBOARD_PORT="$(choose_port "Toolbox Dashboard" 30042)"
  if $ENABLE_FOLDER; then
    LIB_JSON="$(curl -fsS --max-time 10 -H "x-api-key: $API_KEY" "${BROWSER_URL}/api/libraries" 2>/dev/null || true)"; LIB_LINES=()
    [[ -n "$LIB_JSON" ]] && mapfile -t LIB_LINES < <(python3 - "$LIB_JSON" <<'PY'
import json,sys
try:d=json.loads(sys.argv[1])
except Exception:d=[]
if isinstance(d,dict): d=d.get('libraries',d.get('items',[]))
for lib in d if isinstance(d,list) else []:
  if isinstance(lib,dict):
    for p in lib.get('importPaths') or lib.get('import_paths') or []:
      if isinstance(p,str) and p: print((lib.get('name') or 'External Library')+'\t'+p)
PY
)
    if ((${#LIB_LINES[@]})); then say "External Libraries found:"; i=1; for row in "${LIB_LINES[@]}"; do printf '  [%d] %s\n      %s\n' "$i" "${row%%$'\t'*}" "${row#*$'\t'}"; ((i++)); done; read -rp "Choose import path [1]: " LI; LI="${LI:-1}"; row="${LIB_LINES[$((LI-1))]}"; DETECTED_LIB="${row%%$'\t'*}"; ROOT="${row#*$'\t'}"; fi
    read -rp "External Library root${ROOT:+ [$ROOT]}: " X; ROOT="${X:-$ROOT}"; [[ -n "$ROOT" ]] || die "External Library root required."
    read -rp "Album level [1]: " LEVEL; LEVEL="${LEVEL:-1}"; say "1) Daily 03:00  2) Every 6h  3) Hourly  4) Custom"; read -rp "Choice [1]: " SC; case "${SC:-1}" in 2) CRON='0 */6 * * *'; SCHEDULE_LABEL='Every 6 hours';; 3) CRON='0 * * * *'; SCHEDULE_LABEL='Hourly';; 4) read -rp "Cron: " CRON; SCHEDULE_LABEL="$CRON";; *) CRON='0 3 * * *'; SCHEDULE_LABEL='Daily at 03:00';; esac
    yesno "Run album sync immediately?" Y && RUN_NOW=true || RUN_NOW=false; yesno "Random album thumbnail?" Y && THUMB=random || THUMB=""
  fi
  $ENABLE_PET && PET_PORT="$(choose_port "Pet Tagger" 2287)"
  if $ENABLE_POWER; then POWER_PORT="$(choose_port "Power Tools" 8001)"; DB_CONT="$($SUDO docker ps --format '{{.Names}}' | grep -E '^ix-immich-.*(postgres|pgvecto|database|db).*$' | head -1 || true)"; if [[ -n "$DB_CONT" ]]; then DB_NET="$($SUDO docker inspect "$DB_CONT" --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{"\n"}}{{end}}' | head -1)"; ENV="$($SUDO docker inspect "$DB_CONT" --format '{{range .Config.Env}}{{println .}}{{end}}')"; DB_USER="$(sed -n 's/^POSTGRES_USER=//p' <<<"$ENV" | head -1)"; DB_PASS="$(sed -n 's/^POSTGRES_PASSWORD=//p' <<<"$ENV" | head -1)"; DB_NAME="$(sed -n 's/^POSTGRES_DB=//p' <<<"$ENV" | head -1)"; DB_HOST="$DB_CONT"; fi; read -rp "DB host [${DB_HOST:-immich-postgres}]: " X; DB_HOST="${X:-${DB_HOST:-immich-postgres}}"; read -rp "DB port [5432]: " X; DB_PORT="${X:-5432}"; read -rp "DB user [${DB_USER:-postgres}]: " X; DB_USER="${X:-${DB_USER:-postgres}}"; [[ -n "$DB_PASS" ]] || { read -rsp "DB password: " DB_PASS; say; }; read -rp "DB name [${DB_NAME:-immich}]: " X; DB_NAME="${X:-${DB_NAME:-immich}}"; fi
fi

INTERNAL_API="${INTERNAL_BASE%/}/api"
CFG="$(mktemp)"; PAYLOAD="$(mktemp)"; trap 'rm -f "$CFG" "$PAYLOAD"' EXIT
python3 - "$CFG" "$API_KEY" "$BROWSER_URL" "$INTERNAL_BASE" "$INTERNAL_API" "$ENABLE_FOLDER" "$ENABLE_PET" "$ENABLE_POWER" "$DASHBOARD_PORT" "$DETECTED_IP" "$TIMEZONE" "$ROOT" "$LEVEL" "$CRON" "$RUN_NOW" "$THUMB" "$PET_PORT" "$POWER_PORT" "$DB_HOST" "$DB_PORT" "$DB_USER" "$DB_PASS" "$DB_NAME" "$DB_NET" "$DETECTED_LIB" <<'PY'
import json,sys
k=['api','browser','internal','internal_api','folder','pet','power','dashboard_port','host_ip','timezone','root','level','cron','run','thumb','pet_port','power_port','db_host','db_port','db_user','db_pass','db_name','db_net','library']
v=sys.argv[2:]
d=dict(zip(k,v)); d['folder']=d['folder']=='true'; d['pet']=d['pet']=='true'; d['power']=d['power']=='true'; d['dashboard_port']=int(d['dashboard_port']);
for x in ('pet_port','power_port'):
  if d[x]: d[x]=int(d[x])
json.dump(d,open(sys.argv[1],'w'))
PY

python3 - "$CFG" "$PAYLOAD" "$FOLDER_IMAGE" "$PET_IMAGE" "$POWER_IMAGE" "$DASHBOARD_IMAGE" "$TOOLBOX_VERSION" <<'PY'
import json,sys,base64,html
c=json.load(open(sys.argv[1])); version=sys.argv[7]; host=c.get('host_ip') or '127.0.0.1'; services={}; volumes={}; networks={}; eh=['host.docker.internal:host-gateway']
def esc(x): return html.escape(str(x or ''))
modules=[]
if c['folder']: modules.append(('Folder → Album Sync','Background service','Configured','/external/fotos' if not c.get('root') else c['root']))
if c['pet']: modules.append(('Pet Tagger',f'http://{host}:{c["pet_port"]}','Open tool',f':{c["pet_port"]}'))
if c['power']: modules.append(('Immich Power Tools',f'http://{host}:{c["power_port"]}','Open tool',f':{c["power_port"]}'))
logo='''<svg viewBox="0 0 64 64" aria-hidden="true"><defs><linearGradient id="g" x1="0" x2="1"><stop stop-color="#22c55e"/><stop offset="1" stop-color="#3b82f6"/></linearGradient></defs><rect x="4" y="4" width="56" height="56" rx="16" fill="url(#g)"/><path d="M18 22h28v6H18zm0 14h18v6H18z" fill="white"/><circle cx="44" cy="39" r="7" fill="white"/><circle cx="44" cy="39" r="3" fill="#3b82f6"/></svg>'''
folder_detail=''
if c['folder']:
  folder_detail=f'''<section class="panel"><div class="panel-title">Folder → Album Sync <span class="pill ok">Enabled</span></div><div class="kv"><span>Library</span><b>{esc(c.get('library') or 'External Library')}</b><span>Root</span><b>{esc(c.get('root'))}</b><span>Album level</span><b>{esc(c.get('level'))}</b><span>Schedule</span><b>{esc(c.get('cron'))}</b><span>Mode</span><b>CREATE only</b><span>Thumbnail</span><b>{esc(c.get('thumb') or 'default')}</b></div><p class="muted">Runs in the background and has no separate web UI. Logs are available in TrueNAS → Apps → immichtoolbox → folderalbums.</p></section>'''
cards=[f'''<a class="card" href="{esc(c['browser'])}"><div class="ico">📷</div><div><h3>Immich</h3><p>{esc(c['browser'])}</p></div><span>Open →</span></a>''',f'''<a class="card" href="{esc(c['browser'])}/user-settings?isOpen=api-keys"><div class="ico">🔑</div><div><h3>API Keys</h3><p>Manage the shared Toolbox key</p></div><span>Open →</span></a>''']
if c['pet']: cards.append(f'''<a class="card" href="http://{host}:{c['pet_port']}"><div class="ico">🐾</div><div><h3>Pet Tagger</h3><p>Port {c['pet_port']} • no built-in login</p></div><span>Open →</span></a>''')
if c['power']: cards.append(f'''<a class="card" href="http://{host}:{c['power_port']}"><div class="ico">🛠️</div><div><h3>Power Tools</h3><p>Port {c['power_port']}</p></div><span>Open →</span></a>''')
page=f'''<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Immich Toolbox</title><style>:root{{--bg:#0b1020;--panel:#111827;--panel2:#172033;--text:#f8fafc;--muted:#94a3b8;--line:#263247;--green:#22c55e;--blue:#60a5fa}}*{{box-sizing:border-box}}body{{margin:0;background:radial-gradient(circle at top right,#18233d,var(--bg) 40%);color:var(--text);font-family:Inter,ui-sans-serif,system-ui,-apple-system,Segoe UI,sans-serif}}main{{max-width:1120px;margin:auto;padding:36px 20px 70px}}header{{display:flex;align-items:center;gap:16px;margin-bottom:28px}}header svg{{width:58px;height:58px}}h1{{margin:0;font-size:34px;letter-spacing:-.8px}}.sub{{color:var(--muted);margin-top:4px}}.top{{display:grid;grid-template-columns:repeat(auto-fit,minmax(180px,1fr));gap:12px;margin:18px 0 28px}}.stat,.panel{{background:rgba(17,24,39,.85);border:1px solid var(--line);border-radius:16px;padding:18px}}.stat span{{display:block;color:var(--muted);font-size:13px;margin-bottom:5px}}.stat b{{font-size:17px}}.grid{{display:grid;grid-template-columns:repeat(auto-fit,minmax(280px,1fr));gap:14px;margin-bottom:18px}}.card{{display:flex;align-items:center;gap:14px;background:var(--panel);border:1px solid var(--line);border-radius:16px;padding:18px;color:inherit;text-decoration:none;transition:.16s}}.card:hover{{transform:translateY(-2px);background:var(--panel2);border-color:#3b82f6}}.card .ico{{font-size:25px}}.card div:nth-child(2){{flex:1}}.card h3{{margin:0 0 5px}}.card p{{margin:0;color:var(--muted);font-size:14px;overflow-wrap:anywhere}}.card>span{{color:var(--blue)}}.panel{{margin-top:16px}}.panel-title{{font-size:20px;font-weight:700;margin-bottom:14px}}.pill{{font-size:12px;padding:4px 8px;border-radius:99px;margin-left:7px}}.pill.ok{{background:#14351f;color:#86efac}}.kv{{display:grid;grid-template-columns:minmax(130px,180px) 1fr;gap:10px 18px}}.kv span{{color:var(--muted)}}.muted{{color:var(--muted);line-height:1.55}}button,.btn{{border:0;border-radius:10px;padding:10px 13px;background:#2563eb;color:white;font-weight:650;cursor:pointer;text-decoration:none;display:inline-block}}button.secondary{{background:#263247}}code{{display:block;background:#090e19;border:1px solid var(--line);padding:12px;border-radius:10px;overflow:auto;color:#cbd5e1;margin:12px 0}}#updateStatus{{margin:10px 0;color:var(--muted)}}footer{{margin-top:28px;color:var(--muted);font-size:13px}}</style></head><body><main><header>{logo}<div><h1>Immich Toolbox</h1><div class="sub">One dashboard for your Immich companion tools</div></div></header><div class="top"><div class="stat"><span>Toolbox version</span><b>v{version}</b></div><div class="stat"><span>Immich</span><b>Connected</b></div><div class="stat"><span>Enabled modules</span><b>{sum([c['folder'],c['pet'],c['power']])}</b></div><div class="stat"><span>Dashboard port</span><b>{c['dashboard_port']}</b></div></div><div class="grid">{''.join(cards)}</div>{folder_detail}<section class="panel"><div class="panel-title">Configuration</div><div class="kv"><span>Immich URL</span><b>{esc(c['browser'])}</b><span>Internal URL</span><b>{esc(c['internal'])}</b><span>Timezone</span><b>{esc(c['timezone'])}</b><span>API key</span><b>Configured • hidden</b></div></section><section class="panel"><div class="panel-title">Updates</div><p class="muted">Check GitHub for a newer Immich Toolbox installer. Updating from the shell preserves your current settings by default.</p><div id="updateStatus">Installed: v{version}</div><button onclick="checkUpdate()">Check for updates</button> <a class="btn" href="https://github.com/Kevin2296/immich-toolbox" target="_blank">GitHub / changelog</a><code>bash &lt;(curl -fsSL https://raw.githubusercontent.com/Kevin2296/immich-toolbox/main/install.sh)</code></section><section class="panel"><div class="panel-title">Access & security</div><p class="muted">Immich uses your normal account. This dashboard and Pet Tagger do not provide their own authentication; keep them LAN-only or protect them with a reverse proxy before exposing them externally.</p></section><footer>Immich Toolbox v{version} • community orchestration project</footer></main><script>async function checkUpdate(){{let el=document.getElementById('updateStatus');el.textContent='Checking…';try{{let t=await fetch('https://raw.githubusercontent.com/Kevin2296/immich-toolbox/main/install.sh?'+Date.now()).then(r=>r.text());let m=t.match(/TOOLBOX_VERSION="([^"]+)"/);if(!m)throw 0;let latest=m[1];el.textContent=latest==='{version}'?'✓ Up to date — v'+latest:'⬆ Update available: v'+latest+' (installed v{version})';}}catch(e){{el.textContent='Could not check GitHub. Use the command below to update manually.'}}}}</script></body></html>'''
encoded=base64.b64encode(page.encode()).decode()
services['dashboard']={'image':sys.argv[6],'restart':'unless-stopped','ports':[f"{c['dashboard_port']}:80"],'command':['/bin/sh','-c',f"echo {encoded} | base64 -d > /usr/share/nginx/html/index.html && nginx -g 'daemon off;'"]}
if c['folder']:
  e={'TZ':c['timezone'],'API_URL':c['internal_api'],'API_KEY':c['api'],'ROOT_PATH':c['root'],'ALBUM_LEVELS':c['level'],'CRON_EXPRESSION':c['cron'],'RUN_IMMEDIATELY':c['run'],'UNATTENDED':'1','MODE':'CREATE','SYNC_MODE':'0','LOG_LEVEL':'INFO'}
  if c.get('thumb'):e['SET_ALBUM_THUMBNAIL']=c['thumb']
  services['folderalbums']={'image':sys.argv[3],'restart':'unless-stopped','extra_hosts':eh,'environment':e}
if c['pet']:
  services['pettagger']={'image':sys.argv[4],'restart':'unless-stopped','extra_hosts':eh,'environment':{'IMMICH_URL':c['internal'],'IMMICH_API_KEY':c['api'],'IMMICH_EXTERNAL_URL':c['browser'],'POLL_INTERVAL':'3600','GPU_WORKERS':'1'},'ports':[f"{c['pet_port']}:8000"],'volumes':['pettagger_data:/data']};volumes['pettagger_data']={}
if c['power']:
  x={'image':sys.argv[5],'restart':'unless-stopped','extra_hosts':eh,'environment':{'IMMICH_URL':c['internal'],'IMMICH_API_KEY':c['api'],'EXTERNAL_IMMICH_URL':c['browser'],'DB_HOST':c['db_host'],'DB_PORT':c['db_port'],'DB_USERNAME':c['db_user'],'DB_PASSWORD':c['db_pass'],'DB_DATABASE_NAME':c['db_name']},'ports':[f"{c['power_port']}:3000"],'volumes':['powertools_data:/app/data']}
  if c.get('db_net'): x['networks']=['default','immich_external']; networks['immich_external']={'external':True,'name':c['db_net']}
  services['powertools']=x;volumes['powertools_data']={}
co={'services':services}
if volumes:co['volumes']=volumes
if networks:co['networks']=networks
json.dump({'app_name':'immichtoolbox','custom_app':True,'custom_compose_config_string':json.dumps(co,indent=2)},open(sys.argv[2],'w'))
PY

say; say "${BOLD}Summary${RESET}"; say "  Immich:      $BROWSER_URL"; say "  Dashboard:   http://${DETECTED_IP}:${DASHBOARD_PORT}"; say "  API key:     configured (hidden)"; $ENABLE_FOLDER && say "  Folder:      $ROOT • $CRON"; $ENABLE_PET && say "  Pet Tagger:  http://${DETECTED_IP}:${PET_PORT}"; $ENABLE_POWER && say "  Power Tools: http://${DETECTED_IP}:${POWER_PORT}"
if [[ "$MODE" == update || "$MODE" == reconfigure ]]; then yesno "Apply update now?" Y || exit 0; $SUDO midclt call -j app.update "$APP_NAME" "$(python3 - "$PAYLOAD" <<'PY'
import json,sys
d=json.load(open(sys.argv[1])); d.pop('app_name',None); print(json.dumps(d))
PY
)"; ok "Immich Toolbox updated successfully."; else yesno "Install now?" Y || exit 0; $SUDO midclt call -j app.create "$(cat "$PAYLOAD")"; ok "Immich Toolbox installed successfully."; fi
say; say "Dashboard: http://${DETECTED_IP}:${DASHBOARD_PORT}"
