#!/usr/bin/env bash
set -Eeuo pipefail

APP_NAME="immichtoolbox"
TOOLBOX_VERSION="0.3.0"
FOLDER_IMAGE="salvoxia/immich-folder-album-creator:1.0.0"
PET_IMAGE="ghcr.io/tedornitier/immich-pet-tagger:cpu"
POWER_IMAGE="ghcr.io/immich-power-tools/immich-power-tools:v0.22.0"
DASHBOARD_IMAGE="nginx:alpine"

BOLD=$'\033[1m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RED=$'\033[31m'; CYAN=$'\033[36m'; RESET=$'\033[0m'
say(){ printf '%s\n' "$*"; }
ok(){ printf '%s✓%s %s\n' "$GREEN" "$RESET" "$*"; }
warn(){ printf '%s!%s %s\n' "$YELLOW" "$RESET" "$*" >&2; }
die(){ printf '%s✗%s %s\n' "$RED" "$RESET" "$*" >&2; exit 1; }

[[ -r /dev/tty ]] && exec </dev/tty
for c in midclt python3 docker curl ss; do command -v "$c" >/dev/null 2>&1 || die "$c is missing."; done
[[ $EUID -eq 0 ]] && SUDO="" || SUDO="sudo"
$SUDO -v

yesno(){
  local p="$1" d="${2:-Y}" a
  if [[ "$d" == Y ]]; then read -rp "$p [Y/n]: " a; a="${a:-Y}"; else read -rp "$p [y/N]: " a; a="${a:-N}"; fi
  [[ "$a" =~ ^[YyJj]$ ]]
}

port_busy(){
  local p="$1"
  ss -ltnH 2>/dev/null | awk '{print $4}' | grep -Eq "(^|:)$p$"
}

choose_port(){
  local label="$1" preferred="$2" allowed="${3:-}" p candidate
  if [[ -n "$allowed" && "$preferred" == "$allowed" ]]; then
    read -rp "$label port [$preferred]: " p
    p="${p:-$preferred}"
    if [[ "$p" == "$allowed" ]]; then printf '%s' "$p"; return 0; fi
  elif ! port_busy "$preferred"; then
    read -rp "$label port [$preferred]: " p
    p="${p:-$preferred}"
  else
    warn "$label port $preferred is already in use."
    candidate=$((preferred+1))
    while port_busy "$candidate"; do candidate=$((candidate+1)); done
    read -rp "$label port [$candidate]: " p
    p="${p:-$candidate}"
  fi
  [[ "$p" =~ ^[0-9]+$ ]] || die "Invalid port: $p"
  [[ -n "$allowed" && "$p" == "$allowed" ]] || { port_busy "$p" && die "Port $p is already in use."; }
  printf '%s' "$p"
}

container_for_service(){
  local service="$1"
  $SUDO docker ps -a --filter "label=com.docker.compose.project=ix-${APP_NAME}" --filter "label=com.docker.compose.service=${service}" --format '{{.Names}}' | head -1
}

published_port(){
  local service="$1" cport="$2" c
  c="$(container_for_service "$service")"
  [[ -n "$c" ]] || return 0
  $SUDO docker port "$c" "${cport}/tcp" 2>/dev/null | head -1 | sed -E 's/.*:([0-9]+)$/\1/' || true
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

INSTALL_MODE=create
OLD_DASH_PORT=""; OLD_PET_PORT=""; OLD_POWER_PORT=""
if $EXISTS; then
  OLD_DASH_PORT="$(published_port dashboard 80)"
  OLD_PET_PORT="$(published_port pettagger 8000)"
  OLD_POWER_PORT="$(published_port powertools 3000)"
  say
  case "$LANG_CODE" in
    nl)
      warn "Er bestaat al een Immich Toolbox app."
      say "  [1] Bestaande app veilig bijwerken (aanbevolen; volumes/data blijven behouden)"
      say "  [2] Stoppen zonder wijzigingen"
      read -rp "Keuze [1]: " UPGRADE_CHOICE;;
    de)
      warn "Eine Immich Toolbox App ist bereits vorhanden."
      say "  [1] Bestehende App sicher aktualisieren (empfohlen; Volumes/Daten bleiben erhalten)"
      say "  [2] Beenden ohne Änderungen"
      read -rp "Auswahl [1]: " UPGRADE_CHOICE;;
    *)
      warn "An Immich Toolbox app already exists."
      say "  [1] Safely update the existing app (recommended; keeps volumes/data)"
      say "  [2] Quit without changes"
      read -rp "Choice [1]: " UPGRADE_CHOICE;;
  esac
  [[ "${UPGRADE_CHOICE:-1}" == 1 ]] || exit 0
  INSTALL_MODE=update
  ok "Existing app will be updated in-place; it will not be deleted."
fi

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
    yesno "Immich Power Tools inschakelen? (geavanceerd; database-toegang nodig)" N && ENABLE_POWER=true || true;;
  de)
    yesno "Ordner → Album Sync aktivieren?" Y && ENABLE_FOLDER=true || true
    yesno "Pet Tagger aktivieren?" Y && ENABLE_PET=true || true
    yesno "Immich Power Tools aktivieren? (erweitert; Datenbankzugriff nötig)" N && ENABLE_POWER=true || true;;
  *)
    yesno "Enable Folder → Album Sync?" Y && ENABLE_FOLDER=true || true
    yesno "Enable Pet Tagger?" Y && ENABLE_PET=true || true
    yesno "Enable Immich Power Tools? (advanced; database access required)" N && ENABLE_POWER=true || true;;
esac

IMMICH_CONTAINER="$($SUDO docker ps --format '{{.Names}}' | grep -E '^ix-immich-server-1$|immich.*server' | head -1 || true)"
DETECTED_PORT=""
if [[ -n "$IMMICH_CONTAINER" ]]; then DETECTED_PORT="$($SUDO docker port "$IMMICH_CONTAINER" 2283/tcp 2>/dev/null | head -1 | sed -E 's/.*:([0-9]+)$/\1/' || true)"; fi
[[ "$DETECTED_PORT" =~ ^[0-9]+$ ]] || DETECTED_PORT="30041"
DETECTED_IP="$(hostname -I 2>/dev/null | tr ' ' '\n' | grep -E '^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.)' | head -1 || true)"
DEFAULT_URL=""; [[ -n "$DETECTED_IP" ]] && DEFAULT_URL="http://${DETECTED_IP}:${DETECTED_PORT}"

say
[[ -n "$DEFAULT_URL" ]] && ok "Detected Immich URL: $DEFAULT_URL"
case "$LANG_CODE" in
  nl) read -rp "Immich URL die je in je browser gebruikt${DEFAULT_URL:+ [$DEFAULT_URL]}: " BROWSER_URL;;
  de) read -rp "Immich-URL, die du im Browser verwendest${DEFAULT_URL:+ [$DEFAULT_URL]}: " BROWSER_URL;;
  *) read -rp "Immich URL you use in your browser${DEFAULT_URL:+ [$DEFAULT_URL]}: " BROWSER_URL;;
esac
BROWSER_URL="${BROWSER_URL:-$DEFAULT_URL}"; BROWSER_URL="${BROWSER_URL%/}"
[[ -n "$BROWSER_URL" ]] || die "Immich URL is required."
if curl -fsS --max-time 7 "${BROWSER_URL}/api/server/ping" >/dev/null 2>&1; then ok "Immich API: ${BROWSER_URL}/api"; else warn "Could not verify Immich API."; yesno "Continue anyway?" N || exit 1; fi
API_SETTINGS_URL="${BROWSER_URL}/user-settings?isOpen=api-keys"

if [[ -n "$IMMICH_CONTAINER" ]]; then INTERNAL_BASE="http://host.docker.internal:${DETECTED_PORT}"; else INTERNAL_BASE="$BROWSER_URL"; fi
say
say "API key settings: ${CYAN}${API_SETTINGS_URL}${RESET}"
say "Internal container URL: $INTERNAL_BASE"
yesno "Advanced: override internal URL?" N && { read -rp "Internal URL [$INTERNAL_BASE]: " X; INTERNAL_BASE="${X:-$INTERNAL_BASE}"; INTERNAL_BASE="${INTERNAL_BASE%/}"; } || true
INTERNAL_API="${INTERNAL_BASE}/api"

say
say "${BOLD}Immich API key${RESET}"
case "$LANG_CODE" in
  nl) say "Maak ÉÉN API-key 'Immich Toolbox'. Omdat Power Tools brede toegang nodig heeft: kies bij voorkeur 'Select all'.";;
  de) say "Erstelle EINEN API-Schlüssel 'Immich Toolbox'. Für Power Tools am besten 'Select all' wählen.";;
  *) say "Create ONE API key named 'Immich Toolbox'. For Power Tools, use 'Select all'.";;
esac
say "  Folder Albums: asset.read, album.read, album.create, album.update, albumAsset.create"
say "  Pet Tagger: asset/person/face read-create-update permissions (+ optional tag permissions)"
$ENABLE_POWER && say "  Power Tools: ${YELLOW}Select all / all API permissions${RESET}"
say "  ${API_SETTINGS_URL}"
read -rp "Press Enter when the API key is ready..." _
read -rsp "API key: " API_KEY; say
[[ -n "$API_KEY" ]] || die "API key cannot be empty."
if curl -fsS --max-time 7 -H "x-api-key: $API_KEY" "${BROWSER_URL}/api/users/me" >/dev/null 2>&1; then ok "API key accepted by Immich."; else warn "API key validation failed."; yesno "Continue anyway?" N || exit 1; fi

TIMEZONE="$(timedatectl show -p Timezone --value 2>/dev/null || true)"
[[ -n "$TIMEZONE" ]] || TIMEZONE="$(cat /etc/timezone 2>/dev/null || true)"
[[ -n "$TIMEZONE" ]] || TIMEZONE="UTC"
ok "Timezone: $TIMEZONE"

DASH_DEFAULT="${OLD_DASH_PORT:-30042}"
DASHBOARD_PORT="$(choose_port "Toolbox Dashboard" "$DASH_DEFAULT" "$OLD_DASH_PORT")"
ok "Dashboard port: $DASHBOARD_PORT"

CFG="$(mktemp)"; COMPOSE="$(mktemp)"; PAYLOAD="$(mktemp)"
trap 'rm -f "$CFG" "$COMPOSE" "$PAYLOAD"' EXIT
python3 - "$CFG" "$API_KEY" "$BROWSER_URL" "$INTERNAL_BASE" "$INTERNAL_API" "$ENABLE_FOLDER" "$ENABLE_PET" "$ENABLE_POWER" "$DASHBOARD_PORT" "$DETECTED_IP" "$TIMEZONE" <<'PY'
import json,sys
json.dump({"api":sys.argv[2],"browser":sys.argv[3],"internal":sys.argv[4],"internal_api":sys.argv[5],"folder":sys.argv[6]=='true',"pet":sys.argv[7]=='true',"power":sys.argv[8]=='true',"dashboard_port":int(sys.argv[9]),"host_ip":sys.argv[10],"timezone":sys.argv[11]},open(sys.argv[1],'w'))
PY

if $ENABLE_FOLDER; then
  say
  LIB_JSON="$(curl -fsS --max-time 10 -H "x-api-key: $API_KEY" "${BROWSER_URL}/api/libraries" 2>/dev/null || true)"
  DETECTED_ROOT=""; DETECTED_LIB=""; LIB_LINES=()
  if [[ -n "$LIB_JSON" ]]; then
    mapfile -t LIB_LINES < <(python3 - "$LIB_JSON" <<'PY'
import json,sys
try:d=json.loads(sys.argv[1])
except Exception:d=[]
if isinstance(d,dict): d=d.get('libraries',d.get('items',[]))
for lib in d if isinstance(d,list) else []:
    if not isinstance(lib,dict): continue
    name=lib.get('name') or 'External Library'
    for p in (lib.get('importPaths') or lib.get('import_paths') or []):
        if isinstance(p,str) and p: print(name+'\t'+p)
PY
)
  fi
  if ((${#LIB_LINES[@]})); then
    say "${BOLD}External Libraries:${RESET}"
    i=1; for row in "${LIB_LINES[@]}"; do printf '  [%d] %s\n      %s\n' "$i" "${row%%$'\t'*}" "${row#*$'\t'}"; ((i++)); done
    read -rp "Choose import path [1]: " LI; LI="${LI:-1}"
    if [[ "$LI" =~ ^[0-9]+$ ]] && ((LI>=1 && LI<=${#LIB_LINES[@]})); then row="${LIB_LINES[$((LI-1))]}"; DETECTED_LIB="${row%%$'\t'*}"; DETECTED_ROOT="${row#*$'\t'}"; ok "Selected: $DETECTED_LIB — $DETECTED_ROOT"; fi
  else warn "External Library paths could not be detected automatically."; fi
  read -rp "External Library root${DETECTED_ROOT:+ [$DETECTED_ROOT]}: " ROOT; ROOT="${ROOT:-$DETECTED_ROOT}"
  [[ -n "$ROOT" ]] || die "External Library root is required."
  read -rp "Album level [1]: " LEVEL; LEVEL="${LEVEL:-1}"
  say "1) Daily 03:00  2) Every 6h  3) Hourly  4) Custom cron"
  read -rp "Choice [1]: " SC
  case "${SC:-1}" in 2) CRON='0 */6 * * *'; SCHEDULE_LABEL='Every 6 hours';; 3) CRON='0 * * * *'; SCHEDULE_LABEL='Hourly';; 4) read -rp "Cron: " CRON; SCHEDULE_LABEL="$CRON";; *) CRON='0 3 * * *'; SCHEDULE_LABEL='Daily at 03:00';; esac
  yesno "Run album sync immediately?" Y && RUN_NOW=true || RUN_NOW=false
  yesno "Random album thumbnail?" Y && THUMB=random || THUMB=""
  python3 - "$CFG" "$ROOT" "$LEVEL" "$CRON" "$RUN_NOW" "$THUMB" "$DETECTED_LIB" "$SCHEDULE_LABEL" <<'PY'
import json,sys;p=sys.argv[1];d=json.load(open(p));d.update(root=sys.argv[2],level=sys.argv[3],cron=sys.argv[4],run=sys.argv[5],thumb=sys.argv[6],library=sys.argv[7] or 'External Library',schedule_label=sys.argv[8]);json.dump(d,open(p,'w'))
PY
fi

if $ENABLE_PET; then
  PET_DEFAULT="${OLD_PET_PORT:-2287}"
  PET_PORT="$(choose_port "Pet Tagger" "$PET_DEFAULT" "$OLD_PET_PORT")"
  ok "Pet Tagger port: $PET_PORT"
  python3 - "$CFG" "$PET_PORT" <<'PY'
import json,sys;p=sys.argv[1];d=json.load(open(p));d['pet_port']=int(sys.argv[2]);json.dump(d,open(p,'w'))
PY
fi

DB_NET=""; DB_CONT=""; DB_HOST=""; DB_USER=""; DB_PASS=""; DB_NAME=""; DB_PORT="5432"
if $ENABLE_POWER; then
  POWER_DEFAULT="${OLD_POWER_PORT:-8001}"
  POWER_PORT="$(choose_port "Power Tools" "$POWER_DEFAULT" "$OLD_POWER_PORT")"
  ok "Power Tools port: $POWER_PORT"
  DB_CONT="$($SUDO docker ps --format '{{.Names}}' | grep -E '^ix-immich-.*(postgres|pgvecto|database|db).*$' | head -1 || true)"
  if [[ -n "$DB_CONT" ]]; then
    DB_NET="$($SUDO docker inspect "$DB_CONT" --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{"\n"}}{{end}}' | head -1)"
    ENV_DUMP="$($SUDO docker inspect "$DB_CONT" --format '{{range .Config.Env}}{{println .}}{{end}}')"
    DB_USER="$(sed -n 's/^POSTGRES_USER=//p' <<<"$ENV_DUMP" | head -1)"
    DB_PASS="$(sed -n 's/^POSTGRES_PASSWORD=//p' <<<"$ENV_DUMP" | head -1)"
    DB_NAME="$(sed -n 's/^POSTGRES_DB=//p' <<<"$ENV_DUMP" | head -1)"
    DB_HOST="$DB_CONT"; ok "PostgreSQL detected: $DB_CONT"
  else warn "Immich PostgreSQL container was not detected automatically."; fi
  read -rp "DB host [${DB_HOST:-immich-postgres}]: " X; DB_HOST="${X:-${DB_HOST:-immich-postgres}}"
  read -rp "DB port [5432]: " X; DB_PORT="${X:-5432}"
  read -rp "DB user [${DB_USER:-postgres}]: " X; DB_USER="${X:-${DB_USER:-postgres}}"
  if [[ -z "$DB_PASS" ]]; then read -rsp "DB password: " DB_PASS; say; else ok "DB password detected (hidden)."; fi
  read -rp "DB name [${DB_NAME:-immich}]: " X; DB_NAME="${X:-${DB_NAME:-immich}}"
  python3 - "$CFG" "$POWER_PORT" "$DB_HOST" "$DB_PORT" "$DB_USER" "$DB_PASS" "$DB_NAME" "$DB_NET" <<'PY'
import json,sys;p=sys.argv[1];d=json.load(open(p));d.update(power_port=int(sys.argv[2]),db_host=sys.argv[3],db_port=sys.argv[4],db_user=sys.argv[5],db_pass=sys.argv[6],db_name=sys.argv[7],db_net=sys.argv[8]);json.dump(d,open(p,'w'))
PY
fi

python3 - "$CFG" "$COMPOSE" "$FOLDER_IMAGE" "$PET_IMAGE" "$POWER_IMAGE" "$DASHBOARD_IMAGE" "$TOOLBOX_VERSION" <<'PY'
import json,sys,base64,html
c=json.load(open(sys.argv[1])); services={}; volumes={}; networks={}; extra=["host.docker.internal:host-gateway"]
host=c.get('host_ip') or '127.0.0.1'; version=sys.argv[7]
def esc(x): return html.escape(str(x or ''))
def button(url,label,secondary=False):
    cls='btn secondary' if secondary else 'btn'
    return f'<a class="{cls}" href="{esc(url)}" target="_blank" rel="noopener">{esc(label)}</a>'
module_cards=[]
folder_status='Enabled' if c['folder'] else 'Disabled'; pet_status='Enabled' if c['pet'] else 'Disabled'; power_status='Enabled' if c['power'] else 'Disabled'
if c['folder']:
    thumb='Random' if c.get('thumb') else 'Default'
    module_cards.append(f'''<section class="card"><div class="head"><div><div class="eyebrow">BACKGROUND SERVICE</div><h2>Folder → Album Sync</h2></div><span class="badge good">Configured</span></div><p class="muted">Turns folders from your Immich External Library into albums. This module has no separate web interface.</p><div class="facts"><div><span>Library</span><strong>{esc(c.get('library'))}</strong></div><div><span>Root</span><strong>{esc(c.get('root'))}</strong></div><div><span>Album level</span><strong>{esc(c.get('level'))}</strong></div><div><span>Schedule</span><strong>{esc(c.get('schedule_label'))}</strong></div><div><span>Mode</span><strong>CREATE only</strong></div><div><span>Thumbnail</span><strong>{thumb}</strong></div></div><div class="note">Runs in the background. Logs are available in TrueNAS → immichtoolbox → folderalbums.</div></section>''')
if c['pet']:
    u=f"http://{host}:{c['pet_port']}"
    module_cards.append(f'''<section class="card"><div class="head"><div><div class="eyebrow">WEB TOOL</div><h2>Pet Tagger</h2></div><span class="badge good">Configured</span></div><p class="muted">Pet recognition companion for Immich.</p><div class="facts"><div><span>URL</span><strong>{esc(u)}</strong></div><div><span>Port</span><strong>{c['pet_port']}</strong></div><div><span>Access</span><strong>No built-in login</strong></div></div><div class="actions">{button(u,'Open Pet Tagger')}</div><div class="note warn">Keep this LAN-only or protect it behind an authenticated reverse proxy.</div></section>''')
if c['power']:
    u=f"http://{host}:{c['power_port']}"
    module_cards.append(f'''<section class="card"><div class="head"><div><div class="eyebrow">WEB TOOL</div><h2>Immich Power Tools</h2></div><span class="badge good">Configured</span></div><p class="muted">Advanced people, album and workflow tools using your Immich database.</p><div class="facts"><div><span>URL</span><strong>{esc(u)}</strong></div><div><span>Port</span><strong>{c['power_port']}</strong></div><div><span>Database</span><strong>{esc(c.get('db_name'))}</strong></div></div><div class="actions">{button(u,'Open Power Tools')}</div></section>''')
immich_btn=button(c['browser'],'Open Immich'); api_btn=button(c['browser']+'/user-settings?isOpen=api-keys','API Keys',True)
page=f'''<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Immich Toolbox</title><style>:root{{--bg:#0b1020;--panel:#121a2c;--panel2:#172136;--line:#26334c;--text:#f6f8fc;--muted:#9aabc5;--accent:#8b5cf6;--warn:#f59e0b}}*{{box-sizing:border-box}}body{{margin:0;background:radial-gradient(circle at 10% 0,#1a1740 0,transparent 28%),var(--bg);color:var(--text);font:15px/1.5 Inter,ui-sans-serif,system-ui,-apple-system,Segoe UI,sans-serif}}main{{max-width:1180px;margin:auto;padding:42px 22px 60px}}.top{{display:flex;justify-content:space-between;gap:24px;align-items:flex-start;margin-bottom:28px}}h1{{font-size:38px;margin:0 0 7px;letter-spacing:-.03em}}h2{{font-size:21px;margin:2px 0 0}}.subtitle,.muted{{color:var(--muted)}}.version{{padding:7px 11px;border:1px solid var(--line);border-radius:999px;color:var(--muted);white-space:nowrap}}.hero{{background:linear-gradient(135deg,#171f36,#121a2c);border:1px solid var(--line);border-radius:22px;padding:24px;margin-bottom:20px;box-shadow:0 18px 60px #0004}}.hero-row{{display:flex;align-items:center;justify-content:space-between;gap:22px;flex-wrap:wrap}}.hero h3{{margin:0 0 5px;font-size:18px}}.actions{{display:flex;gap:10px;flex-wrap:wrap;margin-top:18px}}.btn{{display:inline-block;background:var(--accent);color:white;text-decoration:none;padding:10px 14px;border-radius:10px;font-weight:700}}.btn.secondary{{background:#202b43;border:1px solid #31405e}}.stats{{display:grid;grid-template-columns:repeat(3,1fr);gap:12px;margin-top:20px}}.stat{{background:#0e1628;border:1px solid var(--line);border-radius:13px;padding:13px 15px}}.stat span,.facts span{{display:block;color:var(--muted);font-size:12px;text-transform:uppercase;letter-spacing:.06em;margin-bottom:3px}}.grid{{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:18px}}.card{{background:var(--panel);border:1px solid var(--line);border-radius:18px;padding:21px;min-width:0}}.head{{display:flex;justify-content:space-between;gap:12px;align-items:flex-start}}.eyebrow{{font-size:11px;letter-spacing:.12em;color:#8ea1c1;font-weight:800}}.badge{{font-size:12px;padding:5px 9px;border-radius:999px;border:1px solid var(--line);white-space:nowrap}}.badge.good{{color:#9bf3b0;background:#123421;border-color:#245b36}}.facts{{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:12px;margin-top:18px}}.facts>div{{background:var(--panel2);border:1px solid var(--line);border-radius:11px;padding:11px;overflow:hidden}}.facts strong{{display:block;overflow-wrap:anywhere}}.note{{margin-top:16px;padding:11px 12px;border-radius:10px;background:#0f1728;color:#adc0dd;border:1px solid var(--line)}}.note.warn{{color:#ffd38a;border-color:#5d4314;background:#251c0d}}footer{{color:#71829d;text-align:center;margin-top:28px;font-size:13px}}@media(max-width:760px){{.grid{{grid-template-columns:1fr}}.stats{{grid-template-columns:1fr}}h1{{font-size:31px}}}}</style></head><body><main><div class="top"><div><h1>Immich Toolbox</h1><div class="subtitle">One TrueNAS app for useful Immich companion tools.</div></div><div class="version">Installer v{esc(version)}</div></div><section class="hero"><div class="hero-row"><div><h3>Immich</h3><div class="muted">{esc(c['browser'])}</div></div><div class="actions">{immich_btn}{api_btn}</div></div><div class="stats"><div class="stat"><span>Folder Albums</span><strong>{folder_status}</strong></div><div class="stat"><span>Pet Tagger</span><strong>{pet_status}</strong></div><div class="stat"><span>Power Tools</span><strong>{power_status}</strong></div></div></section><div class="grid">{''.join(module_cards)}</div><footer>Configuration overview only — live container health remains visible in TrueNAS.</footer></main></body></html>'''
encoded=base64.b64encode(page.encode()).decode()
services['dashboard']={"image":sys.argv[6],"restart":"unless-stopped","ports":[f"{c['dashboard_port']}:80"],"command":["/bin/sh","-c",f"echo {encoded} | base64 -d > /usr/share/nginx/html/index.html && nginx -g 'daemon off;'"]}
if c['folder']:
    env={"TZ":c['timezone'],"API_URL":c['internal_api'],"API_KEY":c['api'],"ROOT_PATH":c['root'],"ALBUM_LEVELS":c['level'],"CRON_EXPRESSION":c['cron'],"RUN_IMMEDIATELY":c['run'],"UNATTENDED":"1","MODE":"CREATE","SYNC_MODE":"0","LOG_LEVEL":"INFO"}
    if c.get('thumb'): env['SET_ALBUM_THUMBNAIL']=c['thumb']
    services['folderalbums']={"image":sys.argv[3],"restart":"unless-stopped","extra_hosts":extra,"environment":env}
if c['pet']:
    services['pettagger']={"image":sys.argv[4],"restart":"unless-stopped","extra_hosts":extra,"environment":{"IMMICH_URL":c['internal'],"IMMICH_API_KEY":c['api'],"IMMICH_EXTERNAL_URL":c['browser'],"POLL_INTERVAL":"3600","GPU_WORKERS":"1"},"ports":[f"{c['pet_port']}:8000"],"volumes":["pettagger_data:/data"]}; volumes['pettagger_data']={}
if c['power']:
    x={"image":sys.argv[5],"restart":"unless-stopped","extra_hosts":extra,"environment":{"IMMICH_URL":c['internal'],"IMMICH_API_KEY":c['api'],"EXTERNAL_IMMICH_URL":c['browser'],"DB_HOST":c['db_host'],"DB_PORT":c['db_port'],"DB_USERNAME":c['db_user'],"DB_PASSWORD":c['db_pass'],"DB_DATABASE_NAME":c['db_name']},"ports":[f"{c['power_port']}:3000"],"volumes":["powertools_data:/app/data"]}
    if c.get('db_net'): x['networks']=['default','immich_external']; networks['immich_external']={"external":True,"name":c['db_net']}
    services['powertools']=x; volumes['powertools_data']={}
compose={"services":services}
if volumes: compose['volumes']=volumes
if networks: compose['networks']=networks
json.dump(compose,open(sys.argv[2],'w'),indent=2)
PY

say
say "${BOLD}Installation summary${RESET}"
say "  Immich:       $BROWSER_URL"
say "  Dashboard:    http://${DETECTED_IP:-TRUENAS-IP}:$DASHBOARD_PORT"
say "  Timezone:     $TIMEZONE"
$ENABLE_FOLDER && { say "  Folder Albums: $DETECTED_LIB — $ROOT"; say "                 level $LEVEL • $SCHEDULE_LABEL • CREATE only"; }
$ENABLE_PET && say "  Pet Tagger:    http://${DETECTED_IP:-TRUENAS-IP}:$PET_PORT (no built-in login)"
$ENABLE_POWER && say "  Power Tools:   http://${DETECTED_IP:-TRUENAS-IP}:$POWER_PORT"
say "  API key:       configured and validated (hidden)"
say
if [[ "$INSTALL_MODE" == update ]]; then
  say "Existing app will be updated in-place. Named Toolbox volumes are kept."
  yesno "Apply update now?" Y || exit 0
  python3 - "$COMPOSE" "$PAYLOAD" <<'PY'
import json,sys
compose=open(sys.argv[1]).read()
json.dump({"custom_compose_config_string":compose},open(sys.argv[2],'w'))
PY
  $SUDO midclt call -j app.update "$APP_NAME" "$(cat "$PAYLOAD")"
  ok "Immich Toolbox updated successfully."
else
  yesno "Install now as one TrueNAS App?" Y || exit 0
  python3 - "$COMPOSE" "$PAYLOAD" <<'PY'
import json,sys
compose=open(sys.argv[1]).read()
json.dump({"app_name":"immichtoolbox","custom_app":True,"custom_compose_config_string":compose},open(sys.argv[2],'w'))
PY
  $SUDO midclt call -j app.create "$(cat "$PAYLOAD")"
  ok "Immich Toolbox installed successfully."
fi

say
say "============================================================"
say "${BOLD}Immich Toolbox ready${RESET}"
say "============================================================"
say "Dashboard:   http://${DETECTED_IP:-TRUENAS-IP}:$DASHBOARD_PORT"
$ENABLE_PET && say "Pet Tagger:  http://${DETECTED_IP:-TRUENAS-IP}:$PET_PORT"
$ENABLE_POWER && say "Power Tools: http://${DETECTED_IP:-TRUENAS-IP}:$POWER_PORT"
say "Immich:      $BROWSER_URL"
say
say "Access / users:"
say "  Immich: normal Immich account"
say "  Dashboard: no login (LAN launcher/config overview)"
$ENABLE_PET && say "  Pet Tagger: no built-in login — keep LAN-only or protect with reverse proxy"
$ENABLE_POWER && say "  Power Tools: uses the configured Immich/API + database connection"
say
say "Logs: TrueNAS → Apps → immichtoolbox → Workloads → select the container logs."
