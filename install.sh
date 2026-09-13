#!/usr/bin/env bash
set -Eeuo pipefail

# Immich Toolbox bootstrap v0.5.0
# Loads the tested v0.4.0 installer core and applies compatibility, UX and dashboard fixes.

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

s = s.replace('TOOLBOX_VERSION="0.4.0"', 'TOOLBOX_VERSION="0.5.0"', 1)

old = "d=json.load(open(sys.argv[1])); d.pop('app_name',None); print(json.dumps(d))"
new = "d=json.load(open(sys.argv[1])); d.pop('app_name',None); d.pop('custom_app',None); print(json.dumps(d))"
if old not in s:
    raise SystemExit("Unable to apply app.update payload compatibility fix")
s = s.replace(old, new, 1)

favicon = '''<link rel="icon" type="image/svg+xml" href="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 64 64'%3E%3Cdefs%3E%3ClinearGradient id='g' x1='0' y1='1' x2='1' y2='0'%3E%3Cstop stop-color='%2322c55e'/%3E%3Cstop offset='1' stop-color='%233b82f6'/%3E%3C/linearGradient%3E%3C/defs%3E%3Crect width='64' height='64' rx='16' fill='url(%23g)'/%3E%3Cpath d='M14 20h29v7H14zm0 12h24v7H14z' fill='white'/%3E%3Ccircle cx='46' cy='44' r='8' fill='white'/%3E%3Ccircle cx='46' cy='44' r='3.5' fill='%233b82f6'/%3E%3C/svg%3E">'''
s = s.replace('<title>Immich Toolbox</title><style>', '<title>Immich Toolbox</title>'+favicon+'<style>', 1)

old_js = "let t=await fetch('https://raw.githubusercontent.com/Kevin2296/immich-toolbox/main/install.sh?'+Date.now()).then(r=>r.text());let m=t.match(/TOOLBOX_VERSION=\\\"([^\\\"]+)\\\"/);if(!m)throw 0;let latest=m[1];"
new_js = "let latest=(await fetch('https://raw.githubusercontent.com/Kevin2296/immich-toolbox/main/version.txt?'+Date.now()).then(r=>r.text())).trim();if(!latest)throw 0;"
if old_js not in s:
    raise SystemExit("Unable to apply dashboard update-check fix")
s = s.replace(old_js, new_js, 1)

s = s.replace('One dashboard for your Immich companion tools',
              'Manage your Immich companion tools in one place', 1)

s = s.replace(
    "if c['folder']:\n  folder_detail=",
    "schedule_display={'0 3 * * *':'Daily at 03:00','0 */6 * * *':'Every 6 hours','0 * * * *':'Hourly'}.get(c.get('cron'),c.get('cron'))\nif c['folder']:\n  folder_detail=",
    1
)
s = s.replace("<span>Schedule</span><b>{esc(c.get('cron'))}</b>",
              "<span>Schedule</span><b>{esc(schedule_display)}</b>", 1)

marker = 'has_service(){ [[ -n "$(container_for_service "$1")" ]]; }\n'
helper = '''has_service(){ [[ -n "$(container_for_service "$1")" ]]; }
run_job(){
  local out
  if out="$($SUDO midclt call -j "$@" 2>&1)"; then
    return 0
  fi
  printf '%s\n' "$out" >&2
  return 1
}
service_state(){
  local c
  c="$(container_for_service "$1")"
  [[ -n "$c" ]] || { printf '%s' "not installed"; return 0; }
  $SUDO docker inspect "$c" --format '{{.State.Status}}' 2>/dev/null || printf '%s' "unknown"
}
'''
if marker not in s:
    raise SystemExit("Unable to add clean middleware output helper")
s = s.replace(marker, helper, 1)

s = s.replace('$SUDO midclt call -j app.update "$APP_NAME"', 'run_job app.update "$APP_NAME"', 1)
s = s.replace('$SUDO midclt call -j app.create "$(cat "$PAYLOAD")"', 'run_job app.create "$(cat "$PAYLOAD")"', 1)
s = s.replace('$SUDO midclt call -j app.delete "$APP_NAME"', 'run_job app.delete "$APP_NAME"')

s = s.replace('say; say "${BOLD}Existing configuration detected${RESET}"',
'''say
case "$LANG_CODE" in
  nl) say "${BOLD}Bestaande configuratie gevonden${RESET}";;
  de) say "${BOLD}Vorhandene Konfiguration erkannt${RESET}";;
  *)  say "${BOLD}Existing configuration detected${RESET}";;
esac''', 1)

s = s.replace('say; say "${BOLD}Summary${RESET}";',
'''say
case "$LANG_CODE" in
  nl) say "${BOLD}Overzicht${RESET}";;
  de) say "${BOLD}Zusammenfassung${RESET}";;
  *)  say "${BOLD}Summary${RESET}";;
esac
''', 1)

old_tail = 'say; say "Dashboard: http://${DETECTED_IP}:${DASHBOARD_PORT}"'
new_tail = r'''say
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
    ;;
  de)
    say "Verwaltung:"
    say "  Konfiguration ändern: Installer erneut starten und Option 2 wählen."
    say "  Entfernen:            Installer erneut starten und Option 3 wählen."
    ;;
  *)
    say "Management:"
    say "  Reconfigure: run the installer again and choose option 2."
    say "  Remove:      run the installer again and choose option 3."
    ;;
esac'''
if old_tail not in s:
    raise SystemExit("Unable to apply final status screen")
s = s.replace(old_tail, new_tail, 1)

p.write_text(s)
PY

chmod +x "$TMP"
exec bash "$TMP"
