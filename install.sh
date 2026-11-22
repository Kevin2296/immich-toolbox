#!/usr/bin/env bash
set -Eeuo pipefail

# Immich Toolbox installer for TrueNAS SCALE 25.10+
# Self-contained since v1.1.0: earlier releases downloaded the v0.4.0 core
# (commit 4af5776) at runtime and patched it with string replacements.

APP_NAME="immichtoolbox"
TOOLBOX_VERSION="1.2.0"
# Pinned images are bumped in this repo after checking upstream for breaking
# changes; floating tags (:cpu, :alpine) are refreshed by every update run.
FOLDER_IMAGE="salvoxia/immich-folder-album-creator:2.0.3"
PET_IMAGE="ghcr.io/tedornitier/immich-pet-tagger:cpu"
POWER_IMAGE="ghcr.io/immich-power-tools/immich-power-tools:v0.26.0"
DASHBOARD_IMAGE="nginx:alpine"
REPO_RAW="https://raw.githubusercontent.com/Kevin2296/immich-toolbox/main/install.sh"
CRON_DESCRIPTION="Immich Toolbox auto-update"

BOLD=$'\033[1m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RED=$'\033[31m'; CYAN=$'\033[36m'; RESET=$'\033[0m'
say(){ printf '%s\n' "$*"; }
ok(){ printf '%s✓%s %s\n' "$GREEN" "$RESET" "$*"; }
warn(){ printf '%s!%s %s\n' "$YELLOW" "$RESET" "$*" >&2; }
die(){ printf '%s✗%s %s\n' "$RED" "$RESET" "$*" >&2; exit 1; }

usage(){
  cat <<'EOF'
Usage: install.sh [--update [--yes]] [--lang en|nl|de]

  (no options)   interactive install / update / reconfigure / remove menu
  --update       update the existing installation, keeping its settings
  --yes, -y      with --update: run unattended (for cron); never asks anything,
                 never stops other apps and never changes ROOT_PATH by itself
  --lang CODE    language for messages (en, nl, de)
EOF
}
ARG_MODE=""; ARG_LANG=""; UNATTENDED=false
while (($#)); do
  case "$1" in
    --update) ARG_MODE=update;;
    --yes|-y) UNATTENDED=true;;
    --lang) [[ $# -ge 2 ]] || die "--lang needs a value"; ARG_LANG="$2"; shift;;
    --lang=*) ARG_LANG="${1#--lang=}";;
    -h|--help) usage; exit 0;;
    *) usage >&2; die "Unknown option: $1";;
  esac
  shift
done
[[ -z "$ARG_LANG" || "$ARG_LANG" =~ ^(en|nl|de)$ ]] || die "--lang must be en, nl or de"
if $UNATTENDED && [[ "$ARG_MODE" != update ]]; then die "--yes only works together with --update"; fi

# Interactive runs read answers from the terminal (also when piped through curl).
if ! $UNATTENDED && [[ -r /dev/tty ]] && { true </dev/tty; } 2>/dev/null; then exec </dev/tty; fi
for c in midclt python3 docker curl ss; do command -v "$c" >/dev/null 2>&1 || die "$c is missing."; done
[[ $EUID -eq 0 ]] && SUDO="" || SUDO="sudo"
if [[ -n "$SUDO" ]]; then
  if $UNATTENDED; then sudo -n true 2>/dev/null || die "--yes needs root or passwordless sudo."; else $SUDO -v; fi
fi

yesno(){
  local p="$1" d="${2:-Y}" a
  if $UNATTENDED; then say "$p → ${d} (unattended)"; [[ "$d" == Y ]]; return; fi
  if [[ "$d" == Y ]]; then read -rp "$p [Y/n]: " a; a="${a:-Y}"; else read -rp "$p [y/N]: " a; a="${a:-N}"; fi
  [[ "$a" =~ ^[YyJj]$ ]]
}
port_busy(){ ss -ltnH 2>/dev/null | awk '{print $4}' | grep -Eq "(^|:)$1$"; }
container_for_service(){ $SUDO docker ps -a --filter "label=com.docker.compose.project=ix-${APP_NAME}" --filter "label=com.docker.compose.service=$1" --format '{{.Names}}' | head -1; }
published_port(){ local c; c="$(container_for_service "$1")"; [[ -n "$c" ]] || return 0; $SUDO docker port "$c" "$2/tcp" 2>/dev/null | head -1 | sed -E 's/.*:([0-9]+)$/\1/' || true; }
env_of(){ local c; c="$(container_for_service "$1")"; [[ -n "$c" ]] || return 0; $SUDO docker inspect "$c" --format '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null | sed -n "s/^$2=//p" | head -1; }
has_service(){ [[ -n "$(container_for_service "$1")" ]]; }
run_job(){
  local out
  if out="$($SUDO midclt call -j "$@" 2>&1)"; then
    return 0
  fi
  printf '%s\n' "$out" >&2
  return 1
}
# Localised one-liner: msg "English" "Nederlands" "Deutsch"
msg(){ case "${LANG_CODE:-en}" in nl) printf '%s' "$2";; de) printf '%s' "$3";; *) printf '%s' "$1";; esac; }

# --- Immich API ---------------------------------------------------------------
# The API key is passed to curl on stdin (-H @-) so it never shows up in the
# process list or in shell traces. Prints the response body; HTTP status is
# written to the file named by $HTTP_CODE_FILE.
HTTP_CODE_FILE="$(mktemp)"; trap 'rm -f "$HTTP_CODE_FILE"' EXIT
immich_get(){
  local base="$1" path="$2" out code
  out="$(printf 'x-api-key: %s\n' "$API_KEY" | curl -sS --max-time 10 -H @- -H 'Accept: application/json' -w '\n%{http_code}' "${base%/}${path}" 2>/dev/null)" || out=$'\n000'
  code="${out##*$'\n'}"
  printf '%s' "$code" >"$HTTP_CODE_FILE"
  printf '%s' "${out%$'\n'*}"
}
last_http_code(){ cat "$HTTP_CODE_FILE" 2>/dev/null || printf '000'; }

# External Library import paths as "name<TAB>path" lines.
# GET /api/libraries is admin-only and needs the `library.read` permission.
LIB_LINES=(); LIB_HTTP=""
load_library_paths(){
  local json base
  LIB_LINES=(); LIB_HTTP=""
  for base in "$BROWSER_URL" "http://127.0.0.1:${DETECTED_PORT}"; do
    [[ -n "$base" ]] || continue
    json="$(immich_get "$base" /api/libraries)"; LIB_HTTP="$(last_http_code)"
    [[ "$LIB_HTTP" == 000 ]] && continue
    break
  done
  [[ "$LIB_HTTP" == 200 ]] || return 1
  mapfile -t LIB_LINES < <(python3 -c '
import json,sys
try: d=json.load(sys.stdin)
except Exception: d=[]
if isinstance(d,dict): d=d.get("libraries",d.get("items",[]))
seen=set()
for lib in d if isinstance(d,list) else []:
  if not isinstance(lib,dict): continue
  for p in lib.get("importPaths") or lib.get("import_paths") or []:
    if isinstance(p,str) and p and p not in seen:
      seen.add(p); print((lib.get("name") or "External Library").replace("\t"," ")+"\t"+p)
' <<<"$json")
  ((${#LIB_LINES[@]}))
}
explain_library_failure(){
  case "$LIB_HTTP" in
    401|403) warn "$(msg \
      "Immich refused GET /api/libraries (HTTP $LIB_HTTP). This endpoint needs an API key of an ADMIN user with the 'library.read' permission." \
      "Immich weigert GET /api/libraries (HTTP $LIB_HTTP). Daarvoor is een API-key van een ADMIN-gebruiker met de permissie 'library.read' nodig." \
      "Immich verweigert GET /api/libraries (HTTP $LIB_HTTP). Dafür wird ein API-Key eines ADMIN-Benutzers mit der Berechtigung 'library.read' benötigt.")";;
    200) warn "$(msg "Immich has no External Library with an import path." "Immich heeft geen External Library met een import path." "Immich hat keine External Library mit Importpfad.")";;
    *) warn "$(msg "Could not reach the Immich API to read External Libraries (HTTP ${LIB_HTTP:-000})." "Kon de Immich API niet bereiken om External Libraries te lezen (HTTP ${LIB_HTTP:-000})." "Immich-API für External Libraries nicht erreichbar (HTTP ${LIB_HTTP:-000}).")";;
  esac
}
# Mount points of the Immich server container, as a hint when the API fails.
immich_mount_hints(){
  [[ -n "${IMMICH_CONTAINER:-}" ]] || return 0
  $SUDO docker inspect "$IMMICH_CONTAINER" --format '{{range .Mounts}}{{.Destination}}{{"\n"}}{{end}}' 2>/dev/null \
    | grep -vE '^$|^/(dev|proc|sys|tmp|etc|run)(/|$)|^/usr/src/app/upload|^/data$|^/cache' || true
}
# Exit 0 when every comma-separated entry of $1 equals or lies below one of the
# detected import paths; prints the entries that do not.
roots_mismatch(){
  local root="$1" r row p hit bad=()
  IFS=',' read -ra _roots <<<"$root"
  for r in "${_roots[@]}"; do
    r="${r%/}"; [[ -n "$r" ]] || continue; hit=false
    for row in "${LIB_LINES[@]}"; do p="${row#*$'\t'}"; p="${p%/}"; [[ "$r" == "$p" || "$r" == "$p"/* ]] && { hit=true; break; }; done
    $hit || bad+=("$r")
  done
  ((${#bad[@]})) || return 1
  printf '%s\n' "${bad[@]}"
}
# Names of the libraries whose import paths cover the given roots ("A, B").
library_names_for_root(){
  local row p r
  IFS=',' read -ra _roots <<<"$1"
  for row in "${LIB_LINES[@]}"; do
    p="${row#*$'\t'}"; p="${p%/}"
    for r in "${_roots[@]}"; do
      r="${r%/}"
      if [[ "$r" == "$p" || "$r" == "$p"/* ]]; then printf '%s\n' "${row%%$'\t'*}"; break; fi
    done
  done | awk '!s[$0]++' | paste -sd, - | sed 's/,/, /g'
}
# Interactive choice of import paths. Sets ROOT (comma separated) and DETECTED_LIB.
choose_library_paths(){
  local i=1 row sel n names=() paths=() picked=()
  say "$(msg "External Libraries found in Immich:" "External Libraries gevonden in Immich:" "External Libraries in Immich gefunden:")"
  for row in "${LIB_LINES[@]}"; do printf '  [%d] %s\n      %s\n' "$i" "${row%%$'\t'*}" "${row#*$'\t'}"; ((i++)); done
  if ((${#LIB_LINES[@]} > 1)); then
    read -rp "$(msg "Import paths to use: 'a' = all, or numbers like 1,3 [a]: " "Te gebruiken import paths: 'a' = alle, of nummers zoals 1,3 [a]: " "Zu nutzende Importpfade: 'a' = alle, oder Nummern wie 1,3 [a]: ")" sel; sel="${sel:-a}"
  else
    sel=1
  fi
  [[ "$sel" =~ ^[Aa]$ ]] && sel="$(seq -s, 1 "${#LIB_LINES[@]}")"
  IFS=',' read -ra picked <<<"${sel// /}"
  for n in "${picked[@]}"; do
    if ! [[ "$n" =~ ^[0-9]+$ ]] || ((n < 1 || n > ${#LIB_LINES[@]})); then warn "$(msg "Ignoring invalid choice: $n" "Ongeldige keuze genegeerd: $n" "Ungültige Auswahl ignoriert: $n")"; continue; fi
    row="${LIB_LINES[$((n-1))]}"
    if [[ "${row#*$'\t'}" == *,* ]]; then warn "$(msg "Skipping path with a comma (not supported by ROOT_PATH): ${row#*$'\t'}" "Pad met komma overgeslagen (niet mogelijk in ROOT_PATH): ${row#*$'\t'}" "Pfad mit Komma übersprungen (in ROOT_PATH nicht möglich): ${row#*$'\t'}")"; continue; fi
    paths+=("${row#*$'\t'}"); names+=("${row%%$'\t'*}")
  done
  ((${#paths[@]})) || return 1
  ROOT="$(IFS=,; printf '%s' "${paths[*]}")"
  DETECTED_LIB="$(printf '%s\n' "${names[@]}" | awk '!s[$0]++' | paste -sd, - | sed 's/,/, /g')"
  ROOT_SOURCE=api
}
# Full interactive ROOT_PATH selection used by fresh installs / reconfigure.
select_root_path(){
  if load_library_paths; then
    choose_library_paths || true
  else
    explain_library_failure
    local hints; hints="$(immich_mount_hints)"
    if [[ -n "$hints" ]]; then
      say "$(msg "Folders mounted into the Immich container (the import path is one of these or a subfolder):" "Mappen die in de Immich-container gemount zijn (het import path is een van deze of een submap):" "In den Immich-Container gemountete Ordner (der Importpfad ist einer davon oder ein Unterordner):")"
      while IFS= read -r h; do say "      $h"; done <<<"$hints"
    fi
    say "$(msg "Use exactly the import path shown in Immich → Administration → External Libraries." "Gebruik precies het import path uit Immich → Beheer → External Libraries." "Verwende genau den Importpfad aus Immich → Verwaltung → External Libraries.")"
  fi
  local x
  read -rp "$(msg "External Library root(s), comma separated" "External Library root(s), komma-gescheiden" "External-Library-Root(s), kommagetrennt")${ROOT:+ [$ROOT]}: " x
  if [[ -n "$x" && "$x" != "$ROOT" ]]; then ROOT="$x"; ROOT_SOURCE=manual; fi
  [[ -n "$ROOT" ]] || die "External Library root required."
  if ((${#LIB_LINES[@]})) && mismatch="$(roots_mismatch "$ROOT")"; then
    warn "$(msg "These roots are not an Immich import path (or below one); the album creator will find no photos there:" "Deze roots zijn geen (submap van een) Immich import path; de album-creator vindt daar geen foto's:" "Diese Roots sind kein (Unterordner eines) Immich-Importpfad(s); der Album-Creator findet dort keine Fotos:")"
    while IFS= read -r b; do say "      $b"; done <<<"$mismatch"
    yesno "$(msg "Continue anyway?" "Toch doorgaan?" "Trotzdem fortfahren?")" N || die "Aborted."
  fi
}

# --- Duplicate standalone album creator --------------------------------------
# A separate TrueNAS app (often called `immichalbums`) running the same
# immich-folder-album-creator would do the same work twice.
check_duplicate_album_apps(){
  local rows id state
  rows="$(python3 -c '
import json,sys
try: apps=json.load(sys.stdin)
except Exception: apps=[]
for a in apps if isinstance(apps,list) else []:
  if not isinstance(a,dict): continue
  aid=str(a.get("id") or a.get("name") or "")
  if not aid or aid=="immichtoolbox": continue
  w=a.get("active_workloads") or {}
  imgs=list(w.get("images") or [])+[c.get("image","") for c in (w.get("container_details") or []) if isinstance(c,dict)]
  if aid=="immichalbums" or any("immich-folder-album-creator" in str(i) for i in imgs):
    print(aid+"\t"+str(a.get("state") or "UNKNOWN"))
' <<<"$EXISTING_JSON")"
  # Containers started outside TrueNAS apps (docker run, Portainer, Dockge ...)
  local stray
  stray="$($SUDO docker ps --format '{{.Names}}\t{{.Image}}\t{{.Label "com.docker.compose.project"}}' 2>/dev/null \
    | awk -F'\t' '$2 ~ /immich-folder-album-creator/ && $3 !~ /^ix-/ {print $1}' || true)"
  [[ -n "$rows" || -n "$stray" ]] || return 0
  say
  # fd 3 keeps stdin free for the yes/no prompt inside the loop
  while IFS=$'\t' read -r id state <&3; do
    [[ -n "$id" ]] || continue
    warn "$(msg "Another TrueNAS app runs the Folder → Album creator: '$id' ($state). Together with the Toolbox this does the same work twice." "Een andere TrueNAS-app draait ook de Folder → Album-creator: '$id' ($state). Samen met de Toolbox gebeurt hetzelfde werk dubbel." "Eine andere TrueNAS-App führt ebenfalls den Folder → Album-Creator aus: '$id' ($state). Zusammen mit der Toolbox wird die Arbeit doppelt erledigt.")"
    if [[ "$state" == RUNNING || "$state" == DEPLOYING ]] && $UNATTENDED; then
      warn "$(msg "Not stopping '$id' in unattended mode; run the installer interactively to stop it." "'$id' wordt in onbewaakte modus niet gestopt; draai de installer interactief om hem te stoppen." "'$id' wird im unbeaufsichtigten Modus nicht gestoppt; Installer interaktiv starten.")"
    elif [[ "$state" == RUNNING || "$state" == DEPLOYING ]]; then
      if yesno "$(msg "Stop app '$id' now? (it is not deleted; you can remove it later in TrueNAS → Apps)" "App '$id' nu stoppen? (wordt niet verwijderd; dat kan later in TrueNAS → Apps)" "App '$id' jetzt stoppen? (wird nicht gelöscht; das geht später unter TrueNAS → Apps)")" Y; then
        if run_job app.stop "$id"; then ok "$(msg "App '$id' stopped." "App '$id' gestopt." "App '$id' gestoppt.")"; else warn "$(msg "Could not stop '$id'; stop it in TrueNAS → Apps." "Kon '$id' niet stoppen; stop hem via TrueNAS → Apps." "Konnte '$id' nicht stoppen; bitte unter TrueNAS → Apps stoppen.")"; fi
      fi
    fi
  done 3<<<"$rows"
  [[ -z "$stray" ]] || warn "$(msg "Non-TrueNAS containers running the album creator: $(paste -sd' ' <<<"$stray") — stop them manually to avoid double work." "Containers buiten TrueNAS-apps met de album-creator: $(paste -sd' ' <<<"$stray") — stop die zelf om dubbel werk te voorkomen." "Container außerhalb von TrueNAS-Apps mit dem Album-Creator: $(paste -sd' ' <<<"$stray") — bitte manuell stoppen.")"
}

# --- Pet Tagger backfill ----------------------------------------------------------
# Pet Tagger's background poller only looks at assets uploaded after its last
# poll. Existing photos are only scanned by a manual scan:
#   POST /api/scan {"scan_since":"YYYY-MM-DD"}   (status: GET /api/scan/result)
# A scan is only useful once at least one pet has reference photos.
pet_ready_since(){
  # Prints the earliest pet "since" date (or 1970-01-01) when pets with refs exist.
  local base="http://127.0.0.1:${PET_PORT}" json i
  for i in $(seq 1 10); do
    json="$(curl -fsS --max-time 3 "$base/api/pets" 2>/dev/null)" && break
    json=""; sleep 3
  done
  [[ -n "$json" ]] || return 2
  python3 -c '
import json,re,sys
try: pets=[p for p in (json.load(sys.stdin).get("pets") or []) if p.get("ref_count")]
except Exception: pets=[]
if not pets: sys.exit(1)
d=[p["since"] for p in pets if re.fullmatch(r"\d{4}-\d{2}-\d{2}",str(p.get("since") or ""))]
print(min(d) if len(d)==len(pets) else "1970-01-01")
' <<<"$json"
}
offer_pet_backfill(){
  $ENABLE_PET || return 0
  $UNATTENDED && return 0
  local since rc=0
  say
  since="$(pet_ready_since)" || rc=$?
  if ((rc == 2)); then
    warn "$(msg "Pet Tagger is not reachable yet; start a full scan later from the Toolbox dashboard." "Pet Tagger is nog niet bereikbaar; start later een volledige scan via het Toolbox-dashboard." "Pet Tagger noch nicht erreichbar; vollständigen Scan später im Toolbox-Dashboard starten.")"; return 0
  elif ((rc != 0)); then
    say "$(msg "Pet Tagger: no pets with reference photos yet. Add your pets in Pet Tagger, then start the one-time full scan from the Toolbox dashboard (new uploads are scanned automatically every hour)." \
               "Pet Tagger: nog geen huisdieren met referentiefoto's. Voeg je huisdieren toe in Pet Tagger en start daarna de eenmalige volledige scan via het Toolbox-dashboard (nieuwe uploads worden elk uur automatisch gescand)." \
               "Pet Tagger: noch keine Haustiere mit Referenzfotos. Haustiere in Pet Tagger anlegen und danach den einmaligen vollständigen Scan im Toolbox-Dashboard starten.")"; return 0
  fi
  say "$(msg "Pet Tagger only scans NEW uploads automatically; existing photos need a one-time full scan." "Pet Tagger scant automatisch alleen NIEUWE uploads; bestaande foto's hebben een eenmalige volledige scan nodig." "Pet Tagger scannt automatisch nur NEUE Uploads; vorhandene Fotos brauchen einen einmaligen vollständigen Scan.")"
  if yesno "$(msg "Start a full scan of photos taken since $since now? (can take hours on CPU)" "Nu een volledige scan starten van foto's vanaf $since? (kan op CPU uren duren)" "Jetzt vollständigen Scan der Fotos seit $since starten? (kann auf CPU Stunden dauern)")" N; then
    if curl -fsS --max-time 10 -X POST -H 'Content-Type: application/json' -d "{\"scan_since\":\"$since\"}" "http://127.0.0.1:${PET_PORT}/api/scan" >/dev/null 2>&1; then
      ok "$(msg "Full scan started. Progress: Toolbox dashboard or Pet Tagger sidebar." "Volledige scan gestart. Voortgang: Toolbox-dashboard of de zijbalk van Pet Tagger." "Vollständiger Scan gestartet. Fortschritt: Toolbox-Dashboard oder Pet-Tagger-Seitenleiste.")"
    else
      warn "$(msg "Could not start the scan; use the dashboard button instead." "Kon de scan niet starten; gebruik de knop op het dashboard." "Scan konnte nicht gestartet werden; bitte den Dashboard-Button nutzen.")"
    fi
  fi
}
service_state(){
  local c
  c="$(container_for_service "$1")"
  [[ -n "$c" ]] || { printf '%s' "not installed"; return 0; }
  $SUDO docker inspect "$c" --format '{{.State.Status}}' 2>/dev/null || printf '%s' "unknown"
}

# --- Image refresh ------------------------------------------------------------
# "service<TAB>image" for every enabled module.
enabled_images(){
  printf 'dashboard\t%s\n' "$DASHBOARD_IMAGE"
  if $ENABLE_FOLDER; then printf 'folderalbums\t%s\n' "$FOLDER_IMAGE"; fi
  if $ENABLE_PET; then printf 'pettagger\t%s\n' "$PET_IMAGE"; fi
  if $ENABLE_POWER; then printf 'powertools\t%s\n' "$POWER_IMAGE"; fi
}
image_id(){ $SUDO docker image inspect --format '{{.Id}}' "$1" 2>/dev/null || true; }
# Pull the current images so floating tags (:cpu, :alpine) pick up upstream releases.
pull_images(){
  local svc img
  say "$(msg "Checking for newer container images…" "Controleren op nieuwere container-images…" "Suche nach neueren Container-Images…")"
  while IFS=$'\t' read -r svc img; do
    if $SUDO docker pull -q "$img" >/dev/null 2>&1; then
      printf '  %-14s %s\n' "$svc" "$img"
    else
      warn "$(msg "Could not pull $img (offline?); keeping the local image." "Kon $img niet downloaden (offline?); lokale image blijft in gebruik." "$img konnte nicht geladen werden (offline?); lokales Image bleibt.")"
    fi
  done < <(enabled_images)
}
# Services whose running container does not use the current image yet.
stale_services(){
  local svc img c cur want
  while IFS=$'\t' read -r svc img; do
    c="$(container_for_service "$svc")"; [[ -n "$c" ]] || continue
    cur="$($SUDO docker inspect --format '{{.Image}}' "$c" 2>/dev/null || true)"; want="$(image_id "$img")"
    [[ -n "$want" && "$cur" != "$want" ]] && printf '%s\n' "$svc"
  done < <(enabled_images)
  return 0
}

# --- Automatic updates (TrueNAS cron job) -----------------------------------------
cron_job_id(){
  $SUDO midclt call cronjob.query "$(python3 -c 'import json,sys; print(json.dumps([["description","=",sys.argv[1]]]))' "$CRON_DESCRIPTION")" 2>/dev/null \
    | python3 -c 'import json,sys
try: r=json.load(sys.stdin)
except Exception: r=[]
print(r[0]["id"] if r else "")' 2>/dev/null || true
}
# TrueNAS → System → Advanced → Cron Jobs entry that runs `install.sh --update --yes`.
offer_cron_job(){
  $UNATTENDED && return 0
  local id sched hour dow payload cmd
  id="$(cron_job_id)"
  say
  if [[ -n "$id" ]]; then
    ok "$(msg "Automatic updates are enabled (TrueNAS → System → Advanced → Cron Jobs → '$CRON_DESCRIPTION')." "Automatische updates staan aan (TrueNAS → Systeem → Geavanceerd → Cron Jobs → '$CRON_DESCRIPTION')." "Automatische Updates sind aktiv (TrueNAS → System → Erweitert → Cron Jobs → '$CRON_DESCRIPTION').")"
    return 0
  fi
  say "$(msg "Automatic updates: a TrueNAS cron job can run this installer with --update --yes. It keeps your settings, pulls newer images and redeploys only when needed. It runs the latest installer from GitHub (main) as root." \
             "Automatische updates: een TrueNAS-cronjob kan deze installer met --update --yes draaien. Je instellingen blijven behouden, nieuwere images worden opgehaald en alleen als het nodig is wordt opnieuw uitgerold. Hij draait de nieuwste installer van GitHub (main) als root." \
             "Automatische Updates: Ein TrueNAS-Cronjob kann diesen Installer mit --update --yes ausführen. Einstellungen bleiben erhalten, neuere Images werden geladen und nur bei Bedarf neu ausgerollt. Er führt den neuesten Installer von GitHub (main) als root aus.")"
  yesno "$(msg "Enable automatic updates?" "Automatische updates inschakelen?" "Automatische Updates aktivieren?")" N || return 0
  say "  1) $(msg "Weekly, Sunday 04:00" "Wekelijks, zondag 04:00" "Wöchentlich, Sonntag 04:00")  2) $(msg "Daily 04:00" "Dagelijks 04:00" "Täglich 04:00")"
  read -rp "$(msg "Choice" "Keuze" "Auswahl") [1]: " sched
  case "${sched:-1}" in 2) hour=4; dow='*';; *) hour=4; dow=0;; esac
  cmd="bash -c 'f=\$(mktemp) && curl -fsSL ${REPO_RAW} -o \"\$f\" && bash \"\$f\" --update --yes --lang ${LANG_CODE}; r=\$?; rm -f \"\$f\"; exit \$r'"
  payload="$(python3 -c '
import json,sys
print(json.dumps({"enabled":True,"description":sys.argv[1],"command":sys.argv[2],"user":"root",
  "schedule":{"minute":"0","hour":sys.argv[3],"dom":"*","month":"*","dow":sys.argv[4]},
  "stdout":True,"stderr":False}))' "$CRON_DESCRIPTION" "$cmd" "$hour" "$dow")"
  if $SUDO midclt call cronjob.create "$payload" >/dev/null; then
    ok "$(msg "Cron job '$CRON_DESCRIPTION' created. Errors and warnings are mailed by TrueNAS (if e-mail is set up)." "Cronjob '$CRON_DESCRIPTION' aangemaakt. Fouten en waarschuwingen mailt TrueNAS (als e-mail is ingesteld)." "Cronjob '$CRON_DESCRIPTION' angelegt. Fehler und Warnungen verschickt TrueNAS per Mail (falls eingerichtet).")"
  else
    warn "$(msg "Could not create the cron job; add it manually under System → Advanced → Cron Jobs:" "Kon de cronjob niet aanmaken; voeg hem zelf toe onder Systeem → Geavanceerd → Cron Jobs:" "Cronjob konnte nicht angelegt werden; bitte manuell unter System → Erweitert → Cron Jobs anlegen:")"
    say "  $cmd"
  fi
}
remove_cron_job(){
  local id; id="$(cron_job_id)"
  [[ -n "$id" ]] || return 0
  if $SUDO midclt call cronjob.delete "$id" >/dev/null; then ok "$(msg "Automatic-update cron job removed." "Cronjob voor automatische updates verwijderd." "Cronjob für automatische Updates entfernt.")"; fi
}
choose_port(){
  local label="$1" preferred="$2" allowed="${3:-}" p candidate
  if [[ -n "$allowed" && "$preferred" == "$allowed" ]]; then read -rp "$label port [$preferred]: " p; p="${p:-$preferred}"; [[ "$p" == "$allowed" ]] && { printf '%s' "$p"; return; }; fi
  if ! port_busy "$preferred"; then read -rp "$label port [$preferred]: " p; p="${p:-$preferred}"; else warn "$label port $preferred is already in use."; candidate=$((preferred+1)); while port_busy "$candidate"; do candidate=$((candidate+1)); done; read -rp "$label port [$candidate]: " p; p="${p:-$candidate}"; fi
  [[ "$p" =~ ^[0-9]+$ ]] || die "Invalid port: $p"
  [[ -n "$allowed" && "$p" == "$allowed" ]] || { port_busy "$p" && die "Port $p is already in use."; }
  printf '%s' "$p"
}

$UNATTENDED || clear || true
say "${BOLD}Immich Toolbox ${TOOLBOX_VERSION}${RESET}"
say "============================================================"
if [[ -n "$ARG_LANG" ]]; then
  LANG_CODE="$ARG_LANG"
elif $UNATTENDED; then
  LANG_CODE=en
else
  say "Choose language / Kies taal / Sprache wählen"
  say "  [1] English"
  say "  [2] Nederlands"
  say "  [3] Deutsch"
  read -rp "Choice / Keuze / Auswahl [1]: " LC
  case "${LC:-1}" in 2) LANG_CODE=nl;; 3) LANG_CODE=de;; *) LANG_CODE=en;; esac
fi
$UNATTENDED && say "$(date '+%Y-%m-%d %H:%M:%S') unattended update"

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
if [[ "$ARG_MODE" == update ]]; then
  $EXISTS || die "$(msg "--update: Immich Toolbox is not installed yet; run the installer without options first." "--update: Immich Toolbox is nog niet geïnstalleerd; draai de installer eerst zonder opties." "--update: Immich Toolbox ist noch nicht installiert; Installer zuerst ohne Optionen starten.")"
  MODE=update
elif $EXISTS; then
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
        1) yesno "Remove immichtoolbox but keep volumes/data?" N || exit 0; run_job app.delete "$APP_NAME" '{"remove_images":false,"remove_ix_volumes":false,"force_remove_ix_volumes":false,"force_remove_custom_app":false}'; ok "Immich Toolbox removed; TrueNAS-managed volumes were kept."; remove_cron_job; exit 0;;
        2) warn "This can permanently delete Toolbox-managed data."; yesno "Really remove app AND TrueNAS-managed volumes?" N || exit 0; run_job app.delete "$APP_NAME" '{"remove_images":false,"remove_ix_volumes":true,"force_remove_ix_volumes":false,"force_remove_custom_app":false}'; ok "Immich Toolbox and TrueNAS-managed volumes removed."; remove_cron_job; exit 0;;
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
ROOT=""; LEVEL="1"; CRON='0 3 * * *'; SCHEDULE_LABEL='Daily at 03:00'; RUN_NOW="true"; THUMB="random"; DETECTED_LIB=""; ROOT_SOURCE=""
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
  if [[ -z "$API_KEY" ]]; then
    $UNATTENDED && die "Existing API key could not be read; run the installer interactively."
    warn "Existing API key could not be read; asking once."; read -rsp "API key: " API_KEY; say
  fi
  if $ENABLE_FOLDER; then
    if [[ -z "$ROOT" ]]; then
      $UNATTENDED && die "Existing Folder Albums root could not be read; run the installer interactively."
      warn "Existing Folder Albums root could not be read."; select_root_path
    elif load_library_paths; then
      # Verify the stored ROOT_PATH against the real import paths: a mismatch makes
      # the album creator report "0 albums created" on every run.
      if mismatch="$(roots_mismatch "$ROOT")"; then
        warn "$(msg "The current Folder Albums ROOT_PATH does not match any Immich External Library import path:" "Het huidige Folder Albums ROOT_PATH komt niet overeen met een import path van een Immich External Library:" "Der aktuelle Folder-Albums-ROOT_PATH passt zu keinem Importpfad einer Immich External Library:")"
        while IFS= read -r b; do say "      $b"; done <<<"$mismatch"
        say "$(msg "Because of this no albums are created." "Daardoor worden er geen albums aangemaakt." "Deshalb werden keine Alben erstellt.")"
        if $UNATTENDED; then
          warn "$(msg "Keeping ROOT_PATH unchanged in unattended mode; run the installer interactively to fix it." "ROOT_PATH blijft ongewijzigd in onbewaakte modus; draai de installer interactief om het te herstellen." "ROOT_PATH bleibt im unbeaufsichtigten Modus unverändert; Installer interaktiv starten.")"
        elif yesno "$(msg "Choose the correct import path(s) now?" "Nu het juiste import path kiezen?" "Jetzt den richtigen Importpfad wählen?")" Y; then
          choose_library_paths || select_root_path
        fi
      else
        ROOT_SOURCE=api
        DETECTED_LIB="$(library_names_for_root "$ROOT")"
      fi
    else
      explain_library_failure
      warn "$(msg "The current ROOT_PATH ($ROOT) could not be verified." "Het huidige ROOT_PATH ($ROOT) kon niet gecontroleerd worden." "Der aktuelle ROOT_PATH ($ROOT) konnte nicht geprüft werden.")"
    fi
  fi
  say
case "$LANG_CODE" in
  nl) say "${BOLD}Bestaande configuratie gevonden${RESET}";;
  de) say "${BOLD}Vorhandene Konfiguration erkannt${RESET}";;
  *)  say "${BOLD}Existing configuration detected${RESET}";;
esac
  say "  Immich:       $BROWSER_URL"; say "  Internal:     $INTERNAL_BASE"; say "  Dashboard:    :$DASHBOARD_PORT"; case "$LANG_CODE" in
  nl) say "  API key:      ✓ gevonden (verborgen)";;
  de) say "  API key:      ✓ gefunden (verborgen)";;
  *)  say "  API key:      ✓ found (hidden)";;
esac
  $ENABLE_FOLDER && { say "  Folder Albums: enabled"; say "    Root:       $ROOT"; say "    Level:      $LEVEL"; say "    Schedule:   $CRON"; }
  $ENABLE_PET && say "  Pet Tagger:   enabled • :$PET_PORT"
  $ENABLE_POWER && say "  Power Tools:  enabled • :$POWER_PORT • DB $DB_HOST/$DB_NAME"
  say; case "$LANG_CODE" in
  nl) yesno "Deze instellingen behouden en alleen Toolbox/dashboard bijwerken?" Y;;
  de) yesno "Diese Einstellungen behalten und nur Toolbox/Dashboard aktualisieren?" Y;;
  *)  yesno "Keep these settings and update only the Toolbox version/dashboard?" Y;;
esac || { warn "Use option 2 (Reconfigure) instead."; exit 0; }
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
  $ENABLE_FOLDER && say "Folder → Album Sync: use an API key of an ADMIN user and include 'library.read', so the installer can read the External Library import paths."
  read -rsp "API key: " API_KEY; say; [[ -n "$API_KEY" ]] || die "API key required."
  immich_get "$BROWSER_URL" /api/users/me >/dev/null
  if [[ "$(last_http_code)" == 200 ]]; then ok "API key accepted by Immich."; else warn "API key validation failed."; yesno "Continue anyway?" N || exit 1; fi
  DASHBOARD_PORT="$(choose_port "Toolbox Dashboard" 30042)"
  if $ENABLE_FOLDER; then
    select_root_path
    read -rp "Album level [1]: " LEVEL; LEVEL="${LEVEL:-1}"; say "1) Daily 03:00  2) Every 6h  3) Hourly  4) Custom"; read -rp "Choice [1]: " SC; case "${SC:-1}" in 2) CRON='0 */6 * * *'; SCHEDULE_LABEL='Every 6 hours';; 3) CRON='0 * * * *'; SCHEDULE_LABEL='Hourly';; 4) read -rp "Cron: " CRON; SCHEDULE_LABEL="$CRON";; *) CRON='0 3 * * *'; SCHEDULE_LABEL='Daily at 03:00';; esac
    yesno "Run album sync immediately?" Y && RUN_NOW=true || RUN_NOW=false; yesno "Random album thumbnail?" Y && THUMB=random || THUMB=""
  fi
  $ENABLE_PET && PET_PORT="$(choose_port "Pet Tagger" 2287)"
  if $ENABLE_POWER; then POWER_PORT="$(choose_port "Power Tools" 8001)"; DB_CONT="$($SUDO docker ps --format '{{.Names}}' | grep -E '^ix-immich-.*(postgres|pgvecto|database|db).*$' | head -1 || true)"; if [[ -n "$DB_CONT" ]]; then DB_NET="$($SUDO docker inspect "$DB_CONT" --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{"\n"}}{{end}}' | head -1)"; ENV="$($SUDO docker inspect "$DB_CONT" --format '{{range .Config.Env}}{{println .}}{{end}}')"; DB_USER="$(sed -n 's/^POSTGRES_USER=//p' <<<"$ENV" | head -1)"; DB_PASS="$(sed -n 's/^POSTGRES_PASSWORD=//p' <<<"$ENV" | head -1)"; DB_NAME="$(sed -n 's/^POSTGRES_DB=//p' <<<"$ENV" | head -1)"; DB_HOST="$DB_CONT"; fi; read -rp "DB host [${DB_HOST:-immich-postgres}]: " X; DB_HOST="${X:-${DB_HOST:-immich-postgres}}"; read -rp "DB port [5432]: " X; DB_PORT="${X:-5432}"; read -rp "DB user [${DB_USER:-postgres}]: " X; DB_USER="${X:-${DB_USER:-postgres}}"; [[ -n "$DB_PASS" ]] || { read -rsp "DB password: " DB_PASS; say; }; read -rp "DB name [${DB_NAME:-immich}]: " X; DB_NAME="${X:-${DB_NAME:-immich}}"; fi
fi

INTERNAL_API="${INTERNAL_BASE%/}/api"
CFG="$(mktemp)"; PAYLOAD="$(mktemp)"; trap 'rm -f "$CFG" "$PAYLOAD" "$HTTP_CODE_FILE"' EXIT
python3 - "$CFG" "$API_KEY" "$BROWSER_URL" "$INTERNAL_BASE" "$INTERNAL_API" "$ENABLE_FOLDER" "$ENABLE_PET" "$ENABLE_POWER" "$DASHBOARD_PORT" "$DETECTED_IP" "$TIMEZONE" "$ROOT" "$LEVEL" "$CRON" "$RUN_NOW" "$THUMB" "$PET_PORT" "$POWER_PORT" "$DB_HOST" "$DB_PORT" "$DB_USER" "$DB_PASS" "$DB_NAME" "$DB_NET" "$DETECTED_LIB" "$ROOT_SOURCE" <<'PY'
import json,sys
k=['api','browser','internal','internal_api','folder','pet','power','dashboard_port','host_ip','timezone','root','level','cron','run','thumb','pet_port','power_port','db_host','db_port','db_user','db_pass','db_name','db_net','library','root_source']
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
logo='''<svg viewBox="0 0 64 64" aria-hidden="true"><defs><linearGradient id="g" x1="0" x2="1"><stop stop-color="#22c55e"/><stop offset="1" stop-color="#3b82f6"/></linearGradient></defs><rect x="4" y="4" width="56" height="56" rx="16" fill="url(#g)"/><path d="M18 22h28v6H18zm0 14h18v6H18z" fill="white"/><circle cx="44" cy="39" r="7" fill="white"/><circle cx="44" cy="39" r="3" fill="#3b82f6"/></svg>'''
folder_detail=''
schedule_display={'0 3 * * *':'Daily at 03:00','0 */6 * * *':'Every 6 hours','0 * * * *':'Hourly'}.get(c.get('cron'),c.get('cron'))
roots=[r.strip() for r in str(c.get('root') or '').split(',') if r.strip()]
root_html='<br>'.join(f'<span class="path">{esc(r)}</span>' for r in roots) or '<span class="pill warn">not set</span>'
if c.get('root_source')=='api': root_html+='<br><span class="pill ok">Matches an Immich import path</span>'
else: root_html+='<br><span class="pill warn">Not verified against Immich</span>'
if c['folder']:
  folder_detail=f'''<section class="panel"><div class="panel-title">Folder → Album Sync <span class="pill ok">Enabled</span></div><div class="kv"><span>Library</span><b>{esc(c.get('library') or 'External Library')}</b><span>Root path{'s' if len(roots)>1 else ''} (ROOT_PATH)</span><b>{root_html}</b><span>Album level</span><b>{esc(c.get('level'))}</b><span>Schedule</span><b>{esc(schedule_display)}</b><span>Mode</span><b>CREATE only</b><span>Thumbnail</span><b>{esc(c.get('thumb') or 'default')}</b></div><p class="muted">Runs in the background and has no separate web UI. Logs are available in TrueNAS → Apps → immichtoolbox → folderalbums. ROOT_PATH must be exactly an import path of an Immich External Library (Administration → External Libraries) or a folder below it; otherwise every run reports 0 albums. Re-run the installer and choose Update to re-check it.</p></section>'''
pet_detail=''
if c['pet']:
  pet_detail=f'''<section class="panel"><div class="panel-title">Pet Tagger <span class="pill ok">Enabled</span></div><p class="muted">Pet Tagger automatically scans only photos uploaded after its last hourly poll. Photos that were already in Immich are only tagged by a one-time full scan. Enroll your pets with reference photos in Pet Tagger first, then start the scan here (on CPU a large library can take hours).</p><div class="kv"><span>Scan photos taken since</span><b><input id="petSince" type="date" value="1970-01-01"></b><span>Status</span><b id="petStatus">Loading…</b></div><p><button onclick="petScan()">Start full scan</button> <button class="secondary" onclick="petStop()">Stop scan</button> <a class="btn" href="http://{host}:{c['pet_port']}">Open Pet Tagger</a></p></section>'''
cards=[f'''<a class="card" href="{esc(c['browser'])}"><div class="ico">📷</div><div><h3>Immich</h3><p>{esc(c['browser'])}</p></div><span>Open →</span></a>''',f'''<a class="card" href="{esc(c['browser'])}/user-settings?isOpen=api-keys"><div class="ico">🔑</div><div><h3>API Keys</h3><p>Manage the shared Toolbox key</p></div><span>Open →</span></a>''']
if c['pet']: cards.append(f'''<a class="card" href="http://{host}:{c['pet_port']}"><div class="ico">🐾</div><div><h3>Pet Tagger</h3><p>Port {c['pet_port']} • no built-in login</p></div><span>Open →</span></a>''')
if c['power']: cards.append(f'''<a class="card" href="http://{host}:{c['power_port']}"><div class="ico">🛠️</div><div><h3>Power Tools</h3><p>Port {c['power_port']}</p></div><span>Open →</span></a>''')
pet_js='' if not c['pet'] else '''<script>
const PT='/pettagger/api';
function petEl(){return document.getElementById('petStatus')}
async function petRefresh(){
  try{
    const r=await fetch(PT+'/scan/result').then(x=>x.json());
    const counts=Object.entries(r.counts||{}).map(([k,v])=>k.replace(/_/g,' ')+': '+v).join(' • ');
    let t=r.status==='none'?'No manual scan has run since Pet Tagger started':(r.status||'unknown');
    if(r.current_date)t+=' — at '+r.current_date;
    if(r.error)t+=' — '+r.error;
    petEl().textContent=t+(counts?' ('+counts+')':'');
    if(r.status==='running')setTimeout(petRefresh,5000);
  }catch(e){petEl().textContent='Pet Tagger not reachable (is the container running?)'}
}
async function petScan(){
  const since=document.getElementById('petSince').value||'1970-01-01';
  try{
    const pets=(await fetch(PT+'/pets').then(x=>x.json())).pets||[];
    if(!pets.some(p=>p.ref_count)){petEl().textContent='No pets with reference photos yet. Enroll a pet in Pet Tagger first.';return}
    if(!confirm('Scan all photos taken since '+since+' for '+pets.map(p=>p.name).join(', ')+'?'))return;
    const r=await fetch(PT+'/scan',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({scan_since:since})});
    if(!r.ok)throw new Error('HTTP '+r.status);
    petEl().textContent='Scan started…';setTimeout(petRefresh,2000);
  }catch(e){petEl().textContent='Could not start scan: '+e.message}
}
async function petStop(){try{await fetch(PT+'/scan/stop',{method:'POST'});petRefresh()}catch(e){}}
petRefresh();
</script>'''
page=f'''<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Immich Toolbox</title><link rel="icon" type="image/svg+xml" href="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 64 64'%3E%3Cdefs%3E%3ClinearGradient id='g' x1='0' y1='1' x2='1' y2='0'%3E%3Cstop stop-color='%2322c55e'/%3E%3Cstop offset='1' stop-color='%233b82f6'/%3E%3C/linearGradient%3E%3C/defs%3E%3Crect width='64' height='64' rx='16' fill='url(%23g)'/%3E%3Cpath d='M14 20h29v7H14zm0 12h24v7H14z' fill='white'/%3E%3Ccircle cx='46' cy='44' r='8' fill='white'/%3E%3Ccircle cx='46' cy='44' r='3.5' fill='%233b82f6'/%3E%3C/svg%3E"><style>:root{{--bg:#0b1020;--panel:#111827;--panel2:#172033;--text:#f8fafc;--muted:#94a3b8;--line:#263247;--green:#22c55e;--blue:#60a5fa}}*{{box-sizing:border-box}}body{{margin:0;background:radial-gradient(circle at top right,#18233d,var(--bg) 40%);color:var(--text);font-family:Inter,ui-sans-serif,system-ui,-apple-system,Segoe UI,sans-serif}}main{{max-width:1120px;margin:auto;padding:36px 20px 70px}}header{{display:flex;align-items:center;gap:16px;margin-bottom:28px}}header svg{{width:58px;height:58px}}h1{{margin:0;font-size:34px;letter-spacing:-.8px}}.sub{{color:var(--muted);margin-top:4px}}.top{{display:grid;grid-template-columns:repeat(auto-fit,minmax(180px,1fr));gap:12px;margin:18px 0 28px}}.stat,.panel{{background:rgba(17,24,39,.85);border:1px solid var(--line);border-radius:16px;padding:18px}}.stat span{{display:block;color:var(--muted);font-size:13px;margin-bottom:5px}}.stat b{{font-size:17px}}.grid{{display:grid;grid-template-columns:repeat(auto-fit,minmax(280px,1fr));gap:14px;margin-bottom:18px}}.card{{display:flex;align-items:center;gap:14px;background:var(--panel);border:1px solid var(--line);border-radius:16px;padding:18px;color:inherit;text-decoration:none;transition:.16s}}.card:hover{{transform:translateY(-2px);background:var(--panel2);border-color:#3b82f6}}.card .ico{{font-size:25px}}.card div:nth-child(2){{flex:1}}.card h3{{margin:0 0 5px}}.card p{{margin:0;color:var(--muted);font-size:14px;overflow-wrap:anywhere}}.card>span{{color:var(--blue)}}.panel{{margin-top:16px}}.panel-title{{font-size:20px;font-weight:700;margin-bottom:14px}}.pill{{font-size:12px;padding:4px 8px;border-radius:99px;margin-left:7px}}.pill.ok{{background:#14351f;color:#86efac}}.pill.warn{{background:#3a2a10;color:#fcd34d}}.path{{font-family:ui-monospace,Menlo,Consolas,monospace;overflow-wrap:anywhere}}input[type=date]{{background:#090e19;color:var(--text);border:1px solid var(--line);border-radius:8px;padding:6px 8px}}.kv{{display:grid;grid-template-columns:minmax(130px,180px) 1fr;gap:10px 18px}}.kv span{{color:var(--muted)}}.muted{{color:var(--muted);line-height:1.55}}button,.btn{{border:0;border-radius:10px;padding:10px 13px;background:#2563eb;color:white;font-weight:650;cursor:pointer;text-decoration:none;display:inline-block}}button.secondary{{background:#263247}}code{{display:block;background:#090e19;border:1px solid var(--line);padding:12px;border-radius:10px;overflow:auto;color:#cbd5e1;margin:12px 0}}#updateStatus{{margin:10px 0;color:var(--muted)}}footer{{margin-top:28px;color:var(--muted);font-size:13px}}</style></head><body><main><header>{logo}<div><h1>Immich Toolbox</h1><div class="sub">Manage your Immich companion tools in one place</div></div></header><div class="top"><div class="stat"><span>Toolbox version</span><b>v{version}</b></div><div class="stat"><span>Immich</span><b>Connected</b></div><div class="stat"><span>Enabled modules</span><b>{sum([c['folder'],c['pet'],c['power']])}</b></div><div class="stat"><span>Dashboard port</span><b>{c['dashboard_port']}</b></div></div><div class="grid">{''.join(cards)}</div>{folder_detail}{pet_detail}<section class="panel"><div class="panel-title">Configuration</div><div class="kv"><span>Immich URL</span><b>{esc(c['browser'])}</b><span>Internal URL</span><b>{esc(c['internal'])}</b><span>Timezone</span><b>{esc(c['timezone'])}</b><span>API key</span><b>Configured • hidden</b></div></section><section class="panel"><div class="panel-title">Updates</div><p class="muted">Check GitHub for a newer Immich Toolbox installer. Updating from the shell preserves your current settings by default.</p><div id="updateStatus">Installed: v{version}</div><button onclick="checkUpdate()">Check for updates</button> <a class="btn" href="https://github.com/Kevin2296/immich-toolbox" target="_blank">GitHub / changelog</a><code>bash &lt;(curl -fsSL https://raw.githubusercontent.com/Kevin2296/immich-toolbox/main/install.sh)</code></section><section class="panel"><div class="panel-title">Access & security</div><p class="muted">Immich uses your normal account. This dashboard and Pet Tagger do not provide their own authentication; keep them LAN-only or protect them with a reverse proxy before exposing them externally. The dashboard forwards only Pet Tagger's pets list and scan start/stop/status endpoints, which are already reachable without login on the Pet Tagger port.</p></section><footer>Immich Toolbox v{version} • community orchestration project</footer></main><script>async function checkUpdate(){{let el=document.getElementById('updateStatus');el.textContent='Checking…';try{{let latest=(await fetch('https://raw.githubusercontent.com/Kevin2296/immich-toolbox/main/version.txt?'+Date.now()).then(r=>r.text())).trim();if(!latest)throw 0;el.textContent=latest==='{version}'?'✓ Up to date — v'+latest:'⬆ Update available: v'+latest+' (installed v{version})';}}catch(e){{el.textContent='Could not check GitHub. Use the command below to update manually.'}}}}</script>{pet_js}</body></html>'''
encoded=base64.b64encode(page.encode()).decode()
pet_proxy=''
if c['pet']:
  # Only the scan endpoints the dashboard needs; resolved lazily so nginx also
  # starts while the pettagger container is still down.
  for path,method in (('pets','GET'),('scan','POST'),('scan/result','GET'),('scan/stop','POST')):
    pet_proxy+=f'''  location = /pettagger/api/{path} {{
    limit_except {method} {{ deny all; }}
    set $pettagger http://pettagger:8000;
    proxy_pass $pettagger/api/{path};
    proxy_set_header Host $host;
    proxy_read_timeout 30s;
  }}
'''
nginx_conf=f'''server {{
  listen 80 default_server;
  server_name _;
  root /usr/share/nginx/html;
  index index.html;
  log_not_found off;
  resolver 127.0.0.11 valid=30s ipv6=off;

  # Monitoring agents such as Netdata probe these URLs; answer them instead of
  # filling the log with 404s.
  location ~ ^/(stub_status|basic_status|nginx_status)$ {{
    stub_status;
    access_log off;
  }}
  location ~ ^/(server-status|status|status/format/json|php-fpm-status|fpm-status|ping)$ {{
    access_log off;
    return 404;
  }}
  location = /favicon.ico {{
    access_log off;
    return 204;
  }}
{pet_proxy}  location / {{
    try_files $uri $uri/ =404;
  }}
}}
'''
conf_encoded=base64.b64encode(nginx_conf.encode()).decode()
services['dashboard']={'image':sys.argv[6],'restart':'unless-stopped','ports':[f"{c['dashboard_port']}:80"],'command':['/bin/sh','-c',f"echo {encoded} | base64 -d > /usr/share/nginx/html/index.html && echo {conf_encoded} | base64 -d > /etc/nginx/conf.d/default.conf && nginx -g 'daemon off;'"]}
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

say
case "$LANG_CODE" in
  nl) say "${BOLD}Overzicht${RESET}";;
  de) say "${BOLD}Zusammenfassung${RESET}";;
  *)  say "${BOLD}Summary${RESET}";;
esac
 say "  Immich:      $BROWSER_URL"; say "  Dashboard:   http://${DETECTED_IP}:${DASHBOARD_PORT}"; say "  API key:     configured (hidden)"; $ENABLE_FOLDER && say "  Folder:      $ROOT • $CRON"; $ENABLE_PET && say "  Pet Tagger:  http://${DETECTED_IP}:${PET_PORT}"; $ENABLE_POWER && say "  Power Tools: http://${DETECTED_IP}:${POWER_PORT}"
if [[ "$MODE" == update || "$MODE" == reconfigure ]]; then
  yesno "$(msg "Apply update now?" "Update nu uitvoeren?" "Update jetzt ausführen?")" Y || exit 0
  pull_images
  run_job app.update "$APP_NAME" "$(python3 - "$PAYLOAD" <<'PY'
import json,sys
d=json.load(open(sys.argv[1])); d.pop('app_name',None); d.pop('custom_app',None); print(json.dumps(d))
PY
)" || die "$(msg "TrueNAS app.update failed." "TrueNAS app.update is mislukt." "TrueNAS app.update fehlgeschlagen.")"
  # app.update only recreates containers whose compose config changed; containers
  # still on an older image (new :cpu / :alpine pull) need a redeploy.
  STALE="$(stale_services | paste -sd' ' -)"
  if [[ -n "$STALE" ]]; then
    say "$(msg "Newer images for: $STALE — redeploying." "Nieuwere images voor: $STALE — opnieuw uitrollen." "Neuere Images für: $STALE — wird neu ausgerollt.")"
    run_job app.redeploy "$APP_NAME" || warn "$(msg "Redeploy failed; restart the app in TrueNAS → Apps." "Opnieuw uitrollen mislukt; herstart de app via TrueNAS → Apps." "Neu-Ausrollen fehlgeschlagen; App unter TrueNAS → Apps neu starten.")"
  fi
  ok "Immich Toolbox updated successfully."
else
  yesno "Install now?" Y || exit 0
  run_job app.create "$(cat "$PAYLOAD")" || die "TrueNAS app.create failed."
  ok "Immich Toolbox installed successfully."
fi

# Post-deploy checks: duplicate album creator apps, Pet Tagger backfill, auto-updates.
if $ENABLE_FOLDER; then check_duplicate_album_apps; fi
offer_pet_backfill
offer_cron_job
say
say "============================================================"
case "$LANG_CODE" in
  nl) say "${BOLD}Immich Toolbox ${TOOLBOX_VERSION} is klaar${RESET}";;
  de) say "${BOLD}Immich Toolbox ${TOOLBOX_VERSION} ist bereit${RESET}";;
  *)  say "${BOLD}Immich Toolbox ${TOOLBOX_VERSION} is ready${RESET}";;
esac
say "============================================================"
say
say "  Dashboard     http://${DETECTED_IP}:${DASHBOARD_PORT}"
say "  Immich        $BROWSER_URL"
$ENABLE_PET && say "  Pet Tagger    http://${DETECTED_IP}:${PET_PORT}"
$ENABLE_POWER && say "  Power Tools   http://${DETECTED_IP}:${POWER_PORT}"
say
case "$LANG_CODE" in
  nl) say "Containerstatus:";;
  de) say "Containerstatus:";;
  *)  say "Container status:";;
esac
printf '  %-14s %s\n' "dashboard" "$(service_state dashboard)"
$ENABLE_FOLDER && printf '  %-14s %s\n' "folderalbums" "$(service_state folderalbums)"
$ENABLE_PET && printf '  %-14s %s\n' "pettagger" "$(service_state pettagger)"
$ENABLE_POWER && printf '  %-14s %s\n' "powertools" "$(service_state powertools)"
say
case "$LANG_CODE" in
  nl)
    say "Beheer:"
    say "  Configuratie wijzigen: voer de installer opnieuw uit en kies optie 2."
    say "  Verwijderen:           voer de installer opnieuw uit en kies optie 3."
    say "  Logs:                  TrueNAS → Apps → immichtoolbox → Workloads."
    say "  Zonder vragen updaten: install.sh --update --yes (ook voor een cronjob)."
    ;;
  de)
    say "Verwaltung:"
    say "  Konfiguration ändern: Installer erneut starten und Option 2 wählen."
    say "  Entfernen:            Installer erneut starten und Option 3 wählen."
    say "  Ohne Rückfragen:      install.sh --update --yes (auch für Cronjobs)."
    ;;
  *)
    say "Management:"
    say "  Reconfigure: run the installer again and choose option 2."
    say "  Remove:      run the installer again and choose option 3."
    say "  Unattended:  install.sh --update --yes (also for a cron job)."
    ;;
esac
