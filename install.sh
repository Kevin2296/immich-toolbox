#!/usr/bin/env bash
set -Eeuo pipefail

APP_NAME="immichtoolbox"
TOOLBOX_VERSION="0.2.0"
FOLDER_IMAGE="salvoxia/immich-folder-album-creator:1.0.0"
PET_IMAGE="ghcr.io/tedornitier/immich-pet-tagger:cpu"
POWER_IMAGE="ghcr.io/immich-power-tools/immich-power-tools:v0.22.0"

BOLD=$'\033[1m'; DIM=$'\033[2m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RED=$'\033[31m'; CYAN=$'\033[36m'; RESET=$'\033[0m'
say(){ printf '%s\n' "$*"; }; ok(){ printf '%s✓%s %s\n' "$GREEN" "$RESET" "$*"; }; warn(){ printf '%s!%s %s\n' "$YELLOW" "$RESET" "$*"; }; die(){ printf '%s✗%s %s\n' "$RED" "$RESET" "$*" >&2; exit 1; }

[[ -r /dev/tty ]] && exec </dev/tty
[[ "$(uname -s)" == "Linux" ]] || die "This installer must run on TrueNAS SCALE / Community Edition."
for cmd in midclt python3 docker curl; do command -v "$cmd" >/dev/null 2>&1 || die "$cmd is missing."; done
if [[ $EUID -eq 0 ]]; then SUDO=""; else SUDO="sudo"; fi
$SUDO -v

clear || true
say "${BOLD}Immich Toolbox ${TOOLBOX_VERSION}${RESET}"
say "============================================================"
say
say "Choose language / Kies taal / Sprache wählen"
say "  [1] English"
say "  [2] Nederlands"
say "  [3] Deutsch"
read -rp "Choice / Keuze / Auswahl [1]: " LANG_CHOICE
case "${LANG_CHOICE:-1}" in 2) LANG_CODE=nl;; 3) LANG_CODE=de;; *) LANG_CODE=en;; esac

t(){
 local key="$1"
 case "${LANG_CODE}:${key}" in
  en:title) echo "One TrueNAS Custom App with optional Immich extensions.";; nl:title) echo "Eén TrueNAS Custom App met optionele Immich-uitbreidingen.";; de:title) echo "Eine TrueNAS Custom App mit optionalen Immich-Erweiterungen.";;
  en:modules) echo "Available modules:";; nl:modules) echo "Beschikbare modules:";; de:modules) echo "Verfügbare Module:";;
  en:folder_desc) echo "Folder → Album Sync   (external-library folders to albums)";; nl:folder_desc) echo "Map → Album Sync      (external-library mappen naar albums)";; de:folder_desc) echo "Ordner → Album Sync   (External-Library-Ordner zu Alben)";;
  en:pet_desc) echo "Pet Tagger            (pets as People in Immich)";; nl:pet_desc) echo "Pet Tagger            (huisdieren als People in Immich)";; de:pet_desc) echo "Pet Tagger            (Haustiere als Personen in Immich)";;
  en:power_desc) echo "Immich Power Tools    (management/workflows; advanced)";; nl:power_desc) echo "Immich Power Tools    (beheer/workflows; geavanceerd)";; de:power_desc) echo "Immich Power Tools    (Verwaltung/Workflows; erweitert)";;
  en:modular) echo "Everything is modular: install one, two, or all three modules.";; nl:modular) echo "Alles is modulair: installeer één, twee of alle drie de modules.";; de:modular) echo "Alles ist modular: Installiere ein, zwei oder alle drei Module.";;
  en:q_folder) echo "Enable Folder → Album Sync?";; nl:q_folder) echo "Map → Album Sync inschakelen?";; de:q_folder) echo "Ordner → Album Sync aktivieren?";;
  en:q_pet) echo "Enable Pet Tagger?";; nl:q_pet) echo "Pet Tagger inschakelen?";; de:q_pet) echo "Pet Tagger aktivieren?";;
  en:q_power) echo "Enable Immich Power Tools? (advanced; database access required)";; nl:q_power) echo "Immich Power Tools inschakelen? (geavanceerd; database-toegang nodig)";; de:q_power) echo "Immich Power Tools aktivieren? (erweitert; Datenbankzugriff erforderlich)";;
  en:none_selected) echo "No module selected.";; nl:none_selected) echo "Geen module geselecteerd.";; de:none_selected) echo "Kein Modul ausgewählt.";;
  en:api_title) echo "Immich API key";; nl:api_title) echo "Immich API-key";; de:api_title) echo "Immich API-Schlüssel";;
  en:api_intro) echo "Create a dedicated API key in Immich. The required permissions depend on your selected modules.";; nl:api_intro) echo "Maak in Immich een aparte API-key. De benodigde rechten hangen af van je gekozen modules.";; de:api_intro) echo "Erstelle in Immich einen eigenen API-Schlüssel. Die benötigten Rechte hängen von den gewählten Modulen ab.";;
  en:power_all) echo "Power Tools selected: select ALL Immich API permissions for this key.";; nl:power_all) echo "Power Tools geselecteerd: selecteer ALLE Immich API-permissies voor deze key.";; de:power_all) echo "Power Tools ausgewählt: Wähle ALLE Immich API-Berechtigungen für diesen Schlüssel.";;
  en:min_rights) echo "Select at least these permissions:";; nl:min_rights) echo "Selecteer minimaal deze rechten:";; de:min_rights) echo "Wähle mindestens diese Berechtigungen:";;
  en:optional_tags) echo "Optional, only when using Pet Tagger review tags:";; nl:optional_tags) echo "Optioneel, alleen bij gebruik van Pet Tagger review-tags:";; de:optional_tags) echo "Optional, nur bei Verwendung von Pet-Tagger-Prüf-Tags:";;
  en:api_menu) echo "[Enter] I created the API key    [V] Show permissions again    [Q] Quit";; nl:api_menu) echo "[Enter] API-key is aangemaakt    [V] Rechten opnieuw tonen    [Q] Stoppen";; de:api_menu) echo "[Enter] API-Schlüssel erstellt    [V] Rechte erneut anzeigen    [Q] Beenden";;
  en:api_prompt) echo "API key";; nl:api_prompt) echo "API-key";; de:api_prompt) echo "API-Schlüssel";;
  en:exists) echo "The app 'immichtoolbox' already exists. This installer will not overwrite it automatically.";; nl:exists) echo "De app 'immichtoolbox' bestaat al. Deze installer overschrijft hem niet automatisch.";; de:exists) echo "Die App 'immichtoolbox' existiert bereits. Der Installer überschreibt sie nicht automatisch.";;
  en:host_prompt) echo "TrueNAS / Immich IP or hostname (for example 192.168.1.10)";; nl:host_prompt) echo "TrueNAS / Immich IP of hostname (bijvoorbeeld 192.168.1.10)";; de:host_prompt) echo "TrueNAS / Immich IP oder Hostname (z. B. 192.168.1.10)";;
  en:port_prompt) echo "Immich host port";; nl:port_prompt) echo "Immich hostpoort";; de:port_prompt) echo "Immich Host-Port";;
  en:ping_ok) echo "Immich responds successfully";; nl:ping_ok) echo "Immich reageert succesvol";; de:ping_ok) echo "Immich antwortet erfolgreich";;
  en:ping_fail) echo "Immich could not be reached at the entered address.";; nl:ping_fail) echo "Immich kon niet worden bereikt op het ingevoerde adres.";; de:ping_fail) echo "Immich konnte unter der eingegebenen Adresse nicht erreicht werden.";;
  en:continue_anyway) echo "Continue anyway?";; nl:continue_anyway) echo "Toch doorgaan?";; de:continue_anyway) echo "Trotzdem fortfahren?";;
  en:folder_title) echo "Folder → Album Sync";; nl:folder_title) echo "Map → Album Sync";; de:folder_title) echo "Ordner → Album Sync";;
  en:root_prompt) echo "External Library root as Immich sees it";; nl:root_prompt) echo "External Library root zoals Immich hem ziet";; de:root_prompt) echo "External-Library-Stammpfad, wie Immich ihn sieht";;
  en:level_prompt) echo "Album level";; nl:level_prompt) echo "Albumniveau";; de:level_prompt) echo "Album-Ebene";;
  en:schedule) echo "Schedule:";; nl:schedule) echo "Planning:";; de:schedule) echo "Zeitplan:";;
  en:daily) echo "Daily at 03:00";; nl:daily) echo "Dagelijks om 03:00";; de:daily) echo "Täglich um 03:00";;
  en:sixhour) echo "Every 6 hours";; nl:sixhour) echo "Elke 6 uur";; de:sixhour) echo "Alle 6 Stunden";;
  en:hourly) echo "Every hour";; nl:hourly) echo "Elk uur";; de:hourly) echo "Stündlich";;
  en:customcron) echo "Custom cron expression";; nl:customcron) echo "Eigen cron-expressie";; de:customcron) echo "Eigener Cron-Ausdruck";;
  en:choice) echo "Choice";; nl:choice) echo "Keuze";; de:choice) echo "Auswahl";;
  en:run_now) echo "Run album sync immediately after installation?";; nl:run_now) echo "Album-sync direct na installatie uitvoeren?";; de:run_now) echo "Album-Sync direkt nach der Installation ausführen?";;
  en:thumb) echo "Set a random album thumbnail?";; nl:thumb) echo "Random album-thumbnail instellen?";; de:thumb) echo "Zufälliges Album-Vorschaubild setzen?";;
  en:pet_port) echo "Pet Tagger web port";; nl:pet_port) echo "Pet Tagger webpoort";; de:pet_port) echo "Pet Tagger Web-Port";;
  en:pet_note) echo "The Pet Tagger UI has no built-in authentication. Keep it on your LAN or protect it with a reverse proxy.";; nl:pet_note) echo "De Pet Tagger UI heeft geen ingebouwde login. Houd hem op je LAN of beveilig hem via een reverse proxy.";; de:pet_note) echo "Die Pet-Tagger-Oberfläche hat keine integrierte Anmeldung. Nur im LAN nutzen oder per Reverse Proxy absichern.";;
  en:power_title) echo "Immich Power Tools (advanced)";; nl:power_title) echo "Immich Power Tools (geavanceerd)";; de:power_title) echo "Immich Power Tools (erweitert)";;
  en:power_port) echo "Power Tools web port";; nl:power_port) echo "Power Tools webpoort";; de:power_port) echo "Power Tools Web-Port";;
  en:db_detect) echo "Trying to detect the TrueNAS Immich PostgreSQL container...";; nl:db_detect) echo "TrueNAS Immich PostgreSQL-container automatisch detecteren...";; de:db_detect) echo "TrueNAS Immich PostgreSQL-Container wird automatisch gesucht...";;
  en:db_found) echo "PostgreSQL container found";; nl:db_found) echo "PostgreSQL-container gevonden";; de:db_found) echo "PostgreSQL-Container gefunden";;
  en:net_found) echo "Immich Docker network found";; nl:net_found) echo "Immich Docker-netwerk gevonden";; de:net_found) echo "Immich Docker-Netzwerk gefunden";;
  en:db_not_found) echo "PostgreSQL container was not detected automatically.";; nl:db_not_found) echo "PostgreSQL-container niet automatisch gevonden.";; de:db_not_found) echo "PostgreSQL-Container wurde nicht automatisch erkannt.";;
  en:db_host) echo "Database host";; nl:db_host) echo "Database-host";; de:db_host) echo "Datenbank-Host";;
  en:db_user) echo "Database user";; nl:db_user) echo "Database-gebruiker";; de:db_user) echo "Datenbank-Benutzer";;
  en:db_pass) echo "Database password";; nl:db_pass) echo "Database-wachtwoord";; de:db_pass) echo "Datenbank-Passwort";;
  en:db_name) echo "Database name";; nl:db_name) echo "Database-naam";; de:db_name) echo "Datenbankname";;
  en:db_pass_found) echo "Database password detected automatically (not displayed)";; nl:db_pass_found) echo "Database-wachtwoord automatisch gevonden (wordt niet getoond)";; de:db_pass_found) echo "Datenbank-Passwort automatisch erkannt (wird nicht angezeigt)";;
  en:summary) echo "Summary";; nl:summary) echo "Samenvatting";; de:summary) echo "Zusammenfassung";;
  en:install_now) echo "Install now as one TrueNAS App?";; nl:install_now) echo "Nu installeren als één TrueNAS App?";; de:install_now) echo "Jetzt als eine TrueNAS App installieren?";;
  en:creating) echo "Creating TrueNAS app...";; nl:creating) echo "TrueNAS-app wordt aangemaakt...";; de:creating) echo "TrueNAS-App wird erstellt...";;
  en:done) echo "Immich Toolbox installed successfully.";; nl:done) echo "Immich Toolbox is succesvol geïnstalleerd.";; de:done) echo "Immich Toolbox wurde erfolgreich installiert.";;
  en:open_app) echo "Open TrueNAS → Apps → Installed Applications → immichtoolbox";; nl:open_app) echo "Open TrueNAS → Apps → Installed Applications → immichtoolbox";; de:open_app) echo "Öffne TrueNAS → Apps → Installed Applications → immichtoolbox";;
  en:safe_note) echo "Folder Albums safe defaults: MODE=CREATE and SYNC_MODE=0 (no automated cleanup/delete).";; nl:safe_note) echo "Veilige Folder Albums-standaard: MODE=CREATE en SYNC_MODE=0 (geen automatische cleanup/delete).";; de:safe_note) echo "Sichere Folder-Albums-Standards: MODE=CREATE und SYNC_MODE=0 (kein automatisches Cleanup/Löschen).";;
  *) echo "$key";;
 esac
}

ask_yes_no(){ local prompt="$1" default="${2:-Y}" ans; if [[ "$default" == Y ]]; then read -rp "$prompt [Y/n]: " ans; ans="${ans:-Y}"; else read -rp "$prompt [y/N]: " ans; ans="${ans:-N}"; fi; [[ "$ans" =~ ^[YyJj]$ ]]; }

show_permissions(){
 say; say "${BOLD}$(t api_title)${RESET}"; say "$(t api_intro)"; say
 if $ENABLE_POWER; then say "${YELLOW}$(t power_all)${RESET}"; return; fi
 say "$(t min_rights)"; say
 if $ENABLE_FOLDER; then
  say "${BOLD}Folder → Album Sync${RESET}"; printf '  ✓ %s\n' asset.read album.read album.create album.update albumAsset.create; say
 fi
 if $ENABLE_PET; then
  say "${BOLD}Pet Tagger${RESET}"; printf '  ✓ %s\n' asset.read asset.view person.create person.read person.update person.delete person.reassign face.create face.read face.delete; say
  say "$(t optional_tags)"; printf '  ○ %s\n' tag.create tag.asset; say
 fi
}

clear || true
say "${BOLD}Immich Toolbox ${TOOLBOX_VERSION}${RESET}"; say "============================================================"; say "$(t title)"; say
say "$(t modules)"; say "  ${CYAN}[1]${RESET} $(t folder_desc)"; say "  ${CYAN}[2]${RESET} $(t pet_desc)"; say "  ${CYAN}[3]${RESET} $(t power_desc)"; say; say "${DIM}$(t modular)${RESET}"; say

ENABLE_FOLDER=false; ENABLE_PET=false; ENABLE_POWER=false
ask_yes_no "$(t q_folder)" Y && ENABLE_FOLDER=true
ask_yes_no "$(t q_pet)" Y && ENABLE_PET=true
ask_yes_no "$(t q_power)" N && ENABLE_POWER=true
$ENABLE_FOLDER || $ENABLE_PET || $ENABLE_POWER || die "$(t none_selected)"

show_permissions
while true; do say; say "$(t api_menu)"; read -rp "> " API_ACTION; case "${API_ACTION:-}" in [Vv]) show_permissions;; [Qq]) exit 0;; "") break;; esac; done

EXISTING="$($SUDO midclt call app.query 2>/dev/null || echo '[]')"
if python3 - "$APP_NAME" "$EXISTING" <<'PY'
import json,sys
name=sys.argv[1]
try: rows=json.loads(sys.argv[2])
except Exception: rows=[]
sys.exit(0 if any((r.get('id')==name or r.get('name')==name) for r in rows if isinstance(r,dict)) else 1)
PY
then die "$(t exists)"; fi

read -rsp "$(t api_prompt): " API_KEY; say
[[ -n "$API_KEY" ]] || die "$(t api_prompt) cannot be empty."
read -rp "$(t host_prompt): " HOST_NAME
[[ -n "$HOST_NAME" ]] || die "Host/IP cannot be empty."
read -rp "$(t port_prompt) [30041]: " IMMICH_PORT; IMMICH_PORT="${IMMICH_PORT:-30041}"
IMMICH_BASE_URL="http://${HOST_NAME}:${IMMICH_PORT}"; IMMICH_API_URL="${IMMICH_BASE_URL}/api"; CONTAINER_IMMICH_BASE="http://host.docker.internal:${IMMICH_PORT}"; CONTAINER_IMMICH_API="${CONTAINER_IMMICH_BASE}/api"
say
if curl -fsS --max-time 5 "${IMMICH_API_URL}/server/ping" >/dev/null 2>&1; then ok "$(t ping_ok): ${IMMICH_API_URL}"; else warn "$(t ping_fail)"; ask_yes_no "$(t continue_anyway)" N || exit 1; fi

CFG="$(mktemp)"; PAYLOAD="$(mktemp)"; trap 'rm -f "$CFG" "$PAYLOAD"' EXIT
export IT_APP_NAME="$APP_NAME" IT_API_KEY="$API_KEY" IT_IMMICH_BASE="$CONTAINER_IMMICH_BASE" IT_IMMICH_API="$CONTAINER_IMMICH_API" IT_EXTERNAL_IMMICH="$IMMICH_BASE_URL" IT_FOLDER_IMAGE="$FOLDER_IMAGE" IT_PET_IMAGE="$PET_IMAGE" IT_POWER_IMAGE="$POWER_IMAGE" IT_ENABLE_FOLDER="$ENABLE_FOLDER" IT_ENABLE_PET="$ENABLE_PET" IT_ENABLE_POWER="$ENABLE_POWER"
python3 - "$CFG" <<'PY'
import json,os,sys
b=lambda v:str(v).lower()=='true'
d={'app_name':os.environ['IT_APP_NAME'],'api_key':os.environ['IT_API_KEY'],'immich_base':os.environ['IT_IMMICH_BASE'],'immich_api':os.environ['IT_IMMICH_API'],'external_immich':os.environ['IT_EXTERNAL_IMMICH'],'folder_image':os.environ['IT_FOLDER_IMAGE'],'pet_image':os.environ['IT_PET_IMAGE'],'power_image':os.environ['IT_POWER_IMAGE'],'enable_folder':b(os.environ['IT_ENABLE_FOLDER']),'enable_pet':b(os.environ['IT_ENABLE_PET']),'enable_power':b(os.environ['IT_ENABLE_POWER'])}
json.dump(d,open(sys.argv[1],'w'))
PY

if $ENABLE_FOLDER; then
 say; say "${BOLD}$(t folder_title)${RESET}"
 read -rp "$(t root_prompt) [/external/fotos]: " ROOT_PATH; ROOT_PATH="${ROOT_PATH:-/external/fotos}"
 read -rp "$(t level_prompt) [1]: " ALBUM_LEVELS; ALBUM_LEVELS="${ALBUM_LEVELS:-1}"
 say "$(t schedule)"; say "  1) $(t daily)"; say "  2) $(t sixhour)"; say "  3) $(t hourly)"; say "  4) $(t customcron)"
 read -rp "$(t choice) [1]: " SCHED; case "${SCHED:-1}" in 2) CRON_EXPRESSION='0 */6 * * *';; 3) CRON_EXPRESSION='0 * * * *';; 4) read -rp 'Cron: ' CRON_EXPRESSION;; *) CRON_EXPRESSION='0 3 * * *';; esac
 ask_yes_no "$(t run_now)" Y && RUN_IMMEDIATELY=true || RUN_IMMEDIATELY=false
 ask_yes_no "$(t thumb)" Y && ALBUM_THUMB=random || ALBUM_THUMB=''
 python3 - "$CFG" "$ROOT_PATH" "$ALBUM_LEVELS" "$CRON_EXPRESSION" "$RUN_IMMEDIATELY" "$ALBUM_THUMB" <<'PY'
import json,sys
p=sys.argv[1]; d=json.load(open(p)); d.update(root_path=sys.argv[2],album_levels=sys.argv[3],cron=sys.argv[4],run_immediately=sys.argv[5],album_thumb=sys.argv[6]); json.dump(d,open(p,'w'))
PY
fi

if $ENABLE_PET; then
 say; say "${BOLD}Pet Tagger${RESET}"; read -rp "$(t pet_port) [2287]: " PET_PORT; PET_PORT="${PET_PORT:-2287}"; warn "$(t pet_note)"
 python3 - "$CFG" "$PET_PORT" <<'PY'
import json,sys
p=sys.argv[1]; d=json.load(open(p)); d['pet_port']=int(sys.argv[2]); json.dump(d,open(p,'w'))
PY
fi

IMMICH_NETWORK=''; POSTGRES_CONTAINER=''; DB_HOST=''; DB_PORT=5432; DB_USER=''; DB_PASS=''; DB_NAME=''
if $ENABLE_POWER; then
 say; say "${BOLD}$(t power_title)${RESET}"; read -rp "$(t power_port) [8001]: " POWER_PORT; POWER_PORT="${POWER_PORT:-8001}"; say "$(t db_detect)"
 POSTGRES_CONTAINER="$($SUDO docker ps --format '{{.Names}}' | grep -E '^ix-immich-.*(postgres|database|db).*$' | head -1 || true)"
 if [[ -n "$POSTGRES_CONTAINER" ]]; then
  IMMICH_NETWORK="$($SUDO docker inspect "$POSTGRES_CONTAINER" --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{"\n"}}{{end}}' | head -1)"
  ENV_DUMP="$($SUDO docker inspect "$POSTGRES_CONTAINER" --format '{{range .Config.Env}}{{println .}}{{end}}')"; DB_USER="$(printf '%s\n' "$ENV_DUMP"|sed -n 's/^POSTGRES_USER=//p'|head -1)"; DB_PASS="$(printf '%s\n' "$ENV_DUMP"|sed -n 's/^POSTGRES_PASSWORD=//p'|head -1)"; DB_NAME="$(printf '%s\n' "$ENV_DUMP"|sed -n 's/^POSTGRES_DB=//p'|head -1)"; DB_HOST="$POSTGRES_CONTAINER"; ok "$(t db_found): $POSTGRES_CONTAINER"; [[ -n "$IMMICH_NETWORK" ]] && ok "$(t net_found): $IMMICH_NETWORK"
 else warn "$(t db_not_found)"; fi
 read -rp "$(t db_host) [${DB_HOST:-immich-postgres}]: " in; DB_HOST="${in:-${DB_HOST:-immich-postgres}}"; read -rp 'DB port [5432]: ' in; DB_PORT="${in:-5432}"; read -rp "$(t db_user) [${DB_USER:-postgres}]: " in; DB_USER="${in:-${DB_USER:-postgres}}"
 if [[ -z "$DB_PASS" ]]; then read -rsp "$(t db_pass): " DB_PASS; say; else say "$(t db_pass_found)"; fi
 read -rp "$(t db_name) [${DB_NAME:-immich}]: " in; DB_NAME="${in:-${DB_NAME:-immich}}"
 python3 - "$CFG" "$POWER_PORT" "$DB_HOST" "$DB_PORT" "$DB_USER" "$DB_PASS" "$DB_NAME" "$IMMICH_NETWORK" <<'PY'
import json,sys
p=sys.argv[1]; d=json.load(open(p)); d.update(power_port=int(sys.argv[2]),db_host=sys.argv[3],db_port=sys.argv[4],db_user=sys.argv[5],db_pass=sys.argv[6],db_name=sys.argv[7],immich_network=sys.argv[8]); json.dump(d,open(p,'w'))
PY
fi

python3 - "$CFG" "$PAYLOAD" <<'PY'
import json,sys
c=json.load(open(sys.argv[1])); s={}; v={}; n={}; eh=['host.docker.internal:host-gateway']
if c['enable_folder']:
 e={'TZ':'Europe/Amsterdam','API_URL':c['immich_api'],'API_KEY':c['api_key'],'ROOT_PATH':c['root_path'],'ALBUM_LEVELS':c['album_levels'],'CRON_EXPRESSION':c['cron'],'RUN_IMMEDIATELY':c['run_immediately'],'UNATTENDED':'1','MODE':'CREATE','SYNC_MODE':'0','LOG_LEVEL':'INFO'}
 if c.get('album_thumb'): e['SET_ALBUM_THUMBNAIL']=c['album_thumb']
 s['folderalbums']={'image':c['folder_image'],'restart':'unless-stopped','extra_hosts':eh,'environment':e}
if c['enable_pet']:
 s['pettagger']={'image':c['pet_image'],'restart':'unless-stopped','extra_hosts':eh,'environment':{'IMMICH_URL':c['immich_base'],'IMMICH_API_KEY':c['api_key'],'IMMICH_EXTERNAL_URL':c['external_immich'],'POLL_INTERVAL':'3600','GPU_WORKERS':'1'},'ports':[f"{c['pet_port']}:8000"],'volumes':['pettagger_data:/data']}; v['pettagger_data']={}
if c['enable_power']:
 x={'image':c['power_image'],'restart':'unless-stopped','extra_hosts':eh,'environment':{'IMMICH_URL':c['immich_base'],'IMMICH_API_KEY':c['api_key'],'EXTERNAL_IMMICH_URL':c['external_immich'],'DB_HOST':c['db_host'],'DB_PORT':c['db_port'],'DB_USERNAME':c['db_user'],'DB_PASSWORD':c['db_pass'],'DB_DATABASE_NAME':c['db_name']},'ports':[f"{c['power_port']}:3000"],'volumes':['powertools_data:/app/data']}
 if c.get('immich_network'): x['networks']=['default','immich_external']; n['immich_external']={'external':True,'name':c['immich_network']}
 s['powertools']=x; v['powertools_data']={}
compose={'services':s}
if v: compose['volumes']=v
if n: compose['networks']=n
json.dump({'app_name':c['app_name'],'custom_app':True,'custom_compose_config_string':json.dumps(compose,indent=2)},open(sys.argv[2],'w'))
PY

say; say "${BOLD}$(t summary)${RESET}"; $ENABLE_FOLDER && say '  ✓ Folder → Album Sync'; $ENABLE_PET && say '  ✓ Pet Tagger'; $ENABLE_POWER && say '  ✓ Immich Power Tools'; say "  App:    $APP_NAME"; say "  Immich: $IMMICH_BASE_URL"; say
ask_yes_no "$(t install_now)" Y || exit 0
say; say "$(t creating)"; $SUDO midclt call -j app.create "$(cat "$PAYLOAD")"; say; ok "$(t done)"; say; say "${BOLD}$(t open_app)${RESET}"; $ENABLE_PET && say "Pet Tagger UI:  http://${HOST_NAME}:${PET_PORT}"; $ENABLE_POWER && say "Power Tools UI: http://${HOST_NAME}:${POWER_PORT}"; $ENABLE_FOLDER && say 'Folder Albums:  container logs → folderalbums'; say; say "$(t safe_note)"
