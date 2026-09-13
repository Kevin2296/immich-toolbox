#!/usr/bin/env bash
set -Eeuo pipefail
APP_NAME="immichtoolbox"; TOOLBOX_VERSION="0.2.1"
FOLDER_IMAGE="salvoxia/immich-folder-album-creator:1.0.0"
PET_IMAGE="ghcr.io/tedornitier/immich-pet-tagger:cpu"
POWER_IMAGE="ghcr.io/immich-power-tools/immich-power-tools:v0.22.0"
BOLD=$'\033[1m'; DIM=$'\033[2m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RED=$'\033[31m'; CYAN=$'\033[36m'; RESET=$'\033[0m'
say(){ printf '%s\n' "$*"; }; ok(){ printf '%s✓%s %s\n' "$GREEN" "$RESET" "$*"; }; warn(){ printf '%s!%s %s\n' "$YELLOW" "$RESET" "$*"; }; die(){ printf '%s✗%s %s\n' "$RED" "$RESET" "$*" >&2; exit 1; }
[[ -r /dev/tty ]] && exec </dev/tty
for c in midclt python3 docker curl; do command -v "$c" >/dev/null || die "$c missing"; done
[[ $EUID -eq 0 ]] && SUDO="" || SUDO="sudo"; $SUDO -v
clear || true
say "${BOLD}Immich Toolbox ${TOOLBOX_VERSION}${RESET}"; say "============================================================"; say "Choose language / Kies taal / Sprache wählen"; say "  [1] English"; say "  [2] Nederlands"; say "  [3] Deutsch"; read -rp "Choice / Keuze / Auswahl [1]: " lc
case "${lc:-1}" in 2) LANG=nl;;3) LANG=de;;*) LANG=en;; esac
tr(){ case "$LANG:$1" in
nl:title) echo "Eén TrueNAS Custom App met optionele Immich-uitbreidingen.";; de:title) echo "Eine TrueNAS Custom App mit optionalen Immich-Erweiterungen.";; en:title) echo "One TrueNAS Custom App with optional Immich extensions.";;
nl:folder) echo "Map → Album Sync inschakelen?";; de:folder) echo "Ordner → Album Sync aktivieren?";; en:folder) echo "Enable Folder → Album Sync?";;
nl:pet) echo "Pet Tagger inschakelen?";; de:pet) echo "Pet Tagger aktivieren?";; en:pet) echo "Enable Pet Tagger?";;
nl:power) echo "Immich Power Tools inschakelen? (geavanceerd; database-toegang nodig)";; de:power) echo "Immich Power Tools aktivieren? (erweitert; Datenbankzugriff nötig)";; en:power) echo "Enable Immich Power Tools? (advanced; database access required)";;
nl:api) echo "Maak in Immich een aparte API-key met onderstaande rechten.";; de:api) echo "Erstelle in Immich einen separaten API-Schlüssel mit den folgenden Rechten.";; en:api) echo "Create a dedicated Immich API key with the permissions below.";;
nl:all) echo "Omdat Power Tools is geselecteerd: kies ALLE Immich API-permissies (Select all).";; de:all) echo "Da Power Tools ausgewählt ist: ALLE Immich API-Berechtigungen aktivieren (Select all).";; en:all) echo "Because Power Tools is selected: enable ALL Immich API permissions (Select all).";;
nl:steps) echo "Stap voor stap: Accountinstellingen → API Keys → Nieuwe API-key → naam 'Immich Toolbox' → Select all → Aanmaken → key kopiëren.";; de:steps) echo "Schritte: Kontoeinstellungen → API Keys → Neuer API-Schlüssel → Name 'Immich Toolbox' → Select all → Erstellen → Schlüssel kopieren.";; en:steps) echo "Steps: Account Settings → API Keys → New API key → name 'Immich Toolbox' → Select all → Create → copy the key.";;
nl:menu) echo "[Enter] API-key is aangemaakt    [V] Rechten opnieuw tonen    [Q] Stoppen";; de:menu) echo "[Enter] API-Schlüssel erstellt    [V] Rechte erneut anzeigen    [Q] Beenden";; en:menu) echo "[Enter] API key created    [V] Show permissions again    [Q] Quit";;
nl:host) echo "TrueNAS / Immich IP of hostname";; de:host) echo "TrueNAS / Immich IP oder Hostname";; en:host) echo "TrueNAS / Immich IP or hostname";;
nl:root) echo "External Library root zoals Immich hem ziet";; de:root) echo "External-Library-Pfad wie Immich ihn sieht";; en:root) echo "External Library root as Immich sees it";;
*) echo "$1";; esac; }
yesno(){ local p="$1" d="${2:-Y}" a; [[ $d == Y ]] && { read -rp "$p [Y/n]: " a; a="${a:-Y}"; } || { read -rp "$p [y/N]: " a; a="${a:-N}"; }; [[ $a =~ ^[YyJj]$ ]]; }
say "$(tr title)"; say; say "${CYAN}[1]${RESET} Folder → Album Sync"; say "${CYAN}[2]${RESET} Pet Tagger"; say "${CYAN}[3]${RESET} Immich Power Tools"; say
EF=false; EP=false; EW=false; yesno "$(tr folder)" Y && EF=true; yesno "$(tr pet)" Y && EP=true; yesno "$(tr power)" N && EW=true; $EF||$EP||$EW||die "No modules selected"
showperm(){ say; say "${BOLD}Immich API key${RESET}"; say "$(tr api)"; say
$EF && { say "${BOLD}Folder → Album Sync${RESET}"; printf '  ✓ %s\n' asset.read album.read album.create album.update albumAsset.create; say; }
$EP && { say "${BOLD}Pet Tagger${RESET}"; printf '  ✓ %s\n' asset.read asset.view person.create person.read person.update person.delete person.reassign face.create face.read face.delete; say "  ○ tag.create"; say "  ○ tag.asset"; say; }
$EW && { say "${BOLD}Immich Power Tools${RESET}"; say "  ${YELLOW}$(tr all)${RESET}"; say "  $(tr steps)"; say; }; }
showperm; while true; do say "$(tr menu)"; read -rp "> " a; case "${a:-}" in [Vv]) showperm;;[Qq]) exit 0;;"") break;;esac; done
EX="$($SUDO midclt call app.query 2>/dev/null||echo '[]')"; python3 - "$EX" <<'PY' && die "immichtoolbox already exists"
import json,sys
try:r=json.loads(sys.argv[1])
except:r=[]
raise SystemExit(0 if any(x.get('id')=='immichtoolbox' for x in r if isinstance(x,dict)) else 1)
PY
read -rsp "API key: " API; say; [[ -n $API ]]||die "API key empty"
read -rp "$(tr host) [192.168.1.10]: " HOST; [[ -n $HOST ]]||die "Host required"; read -rp "Immich host port [30041]: " PORT; PORT="${PORT:-30041}"
BASE="http://$HOST:$PORT"; APIURL="$BASE/api"; CBASE="http://host.docker.internal:$PORT"; CAPI="$CBASE/api"
curl -fsS --max-time 5 "$APIURL/server/ping" >/dev/null && ok "Immich reachable: $APIURL" || { warn "Immich not reachable"; yesno "Continue anyway?" N||exit 1; }
CFG=$(mktemp); PAY=$(mktemp); trap 'rm -f "$CFG" "$PAY"' EXIT
python3 - "$CFG" "$API" "$CBASE" "$CAPI" "$BASE" "$EF" "$EP" "$EW" <<PY
import json,sys
json.dump(dict(api=sys.argv[2],base=sys.argv[3],apiurl=sys.argv[4],external=sys.argv[5],ef=sys.argv[6]=='true',ep=sys.argv[7]=='true',ew=sys.argv[8]=='true'),open(sys.argv[1],'w'))
PY
if $EF; then read -rp "$(tr root) [/external/fotos]: " ROOT; ROOT="${ROOT:-/external/fotos}"; read -rp "Album level [1]: " LVL; LVL="${LVL:-1}"; say "1) Daily 03:00  2) Every 6h  3) Hourly  4) Custom"; read -rp "Choice [1]: " SC; case "${SC:-1}" in 2) CR='0 */6 * * *';;3) CR='0 * * * *';;4) read -rp "Cron: " CR;;*) CR='0 3 * * *';;esac; yesno "Run album sync immediately?" Y&&RUN=true||RUN=false; yesno "Random album thumbnail?" Y&&TH=random||TH=''; python3 - "$CFG" "$ROOT" "$LVL" "$CR" "$RUN" "$TH" <<'PY'
import json,sys;p=sys.argv[1];d=json.load(open(p));d.update(root=sys.argv[2],lvl=sys.argv[3],cron=sys.argv[4],run=sys.argv[5],thumb=sys.argv[6]);json.dump(d,open(p,'w'))
PY
fi
if $EP; then read -rp "Pet Tagger web port [2287]: " PETPORT; PETPORT="${PETPORT:-2287}"; warn "Pet Tagger UI has no built-in authentication; keep it on your LAN."; python3 - "$CFG" "$PETPORT" <<'PY'
import json,sys;p=sys.argv[1];d=json.load(open(p));d['petport']=int(sys.argv[2]);json.dump(d,open(p,'w'))
PY
fi
if $EW; then read -rp "Power Tools web port [8001]: " PWPORT; PWPORT="${PWPORT:-8001}"; DB="$($SUDO docker ps --format '{{.Names}}'|grep -E '^ix-immich-.*(postgres|database|db).*$'|head -1||true)"; NET=''; U=''; P=''; N=''; if [[ -n $DB ]]; then NET="$($SUDO docker inspect "$DB" --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{"\n"}}{{end}}'|head -1)"; E="$($SUDO docker inspect "$DB" --format '{{range .Config.Env}}{{println .}}{{end}}')"; U="$(sed -n 's/^POSTGRES_USER=//p'<<<"$E"|head -1)"; P="$(sed -n 's/^POSTGRES_PASSWORD=//p'<<<"$E"|head -1)"; N="$(sed -n 's/^POSTGRES_DB=//p'<<<"$E"|head -1)"; ok "PostgreSQL detected: $DB"; fi; read -rp "DB host [${DB:-immich-postgres}]: " x; DBH="${x:-${DB:-immich-postgres}}"; read -rp "DB port [5432]: " x; DBP="${x:-5432}"; read -rp "DB user [${U:-postgres}]: " x; U="${x:-${U:-postgres}}"; [[ -n $P ]]||{ read -rsp "DB password: " P;say; }; read -rp "DB name [${N:-immich}]: " x; N="${x:-${N:-immich}}"; python3 - "$CFG" "$PWPORT" "$DBH" "$DBP" "$U" "$P" "$N" "$NET" <<'PY'
import json,sys;p=sys.argv[1];d=json.load(open(p));d.update(pwport=int(sys.argv[2]),dbh=sys.argv[3],dbp=sys.argv[4],dbu=sys.argv[5],dbpass=sys.argv[6],dbn=sys.argv[7],net=sys.argv[8]);json.dump(d,open(p,'w'))
PY
fi
python3 - "$CFG" "$PAY" "$FOLDER_IMAGE" "$PET_IMAGE" "$POWER_IMAGE" <<'PY'
import json,sys
c=json.load(open(sys.argv[1]));s={};v={};n={};eh=['host.docker.internal:host-gateway']
if c['ef']:
 e={'TZ':'Europe/Amsterdam','API_URL':c['apiurl'],'API_KEY':c['api'],'ROOT_PATH':c['root'],'ALBUM_LEVELS':c['lvl'],'CRON_EXPRESSION':c['cron'],'RUN_IMMEDIATELY':c['run'],'UNATTENDED':'1','MODE':'CREATE','SYNC_MODE':'0','LOG_LEVEL':'INFO'}
 if c.get('thumb'):e['SET_ALBUM_THUMBNAIL']=c['thumb']
 s['folderalbums']={'image':sys.argv[3],'restart':'unless-stopped','extra_hosts':eh,'environment':e}
if c['ep']:
 s['pettagger']={'image':sys.argv[4],'restart':'unless-stopped','extra_hosts':eh,'environment':{'IMMICH_URL':c['base'],'IMMICH_API_KEY':c['api'],'IMMICH_EXTERNAL_URL':c['external'],'POLL_INTERVAL':'3600','GPU_WORKERS':'1'},'ports':[f"{c['petport']}:8000"],'volumes':['pettagger_data:/data']};v['pettagger_data']={}
if c['ew']:
 x={'image':sys.argv[5],'restart':'unless-stopped','extra_hosts':eh,'environment':{'IMMICH_URL':c['base'],'IMMICH_API_KEY':c['api'],'EXTERNAL_IMMICH_URL':c['external'],'DB_HOST':c['dbh'],'DB_PORT':c['dbp'],'DB_USERNAME':c['dbu'],'DB_PASSWORD':c['dbpass'],'DB_DATABASE_NAME':c['dbn']},'ports':[f"{c['pwport']}:3000"],'volumes':['powertools_data:/app/data']};v['powertools_data']={}
 if c.get('net'):x['networks']=['default','immich_external'];n['immich_external']={'external':True,'name':c['net']}
 s['powertools']=x
co={'services':s};
if v:co['volumes']=v
if n:co['networks']=n
json.dump({'app_name':'immichtoolbox','custom_app':True,'custom_compose_config_string':json.dumps(co,indent=2)},open(sys.argv[2],'w'))
PY
say; say "${BOLD}Summary${RESET}"; $EF&&say "  ✓ Folder → Album Sync"; $EP&&say "  ✓ Pet Tagger"; $EW&&say "  ✓ Immich Power Tools"; yesno "Install now as one TrueNAS App?" Y||exit 0
$SUDO midclt call -j app.create "$(cat "$PAY")"; ok "Immich Toolbox installed"; $EP&&say "Pet Tagger UI: http://$HOST:$PETPORT"; $EW&&say "Power Tools UI: http://$HOST:$PWPORT"
