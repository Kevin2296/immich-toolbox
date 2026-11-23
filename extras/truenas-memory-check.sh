#!/usr/bin/env bash
# TrueNAS memory check (read-only)
#
# Shows where the memory of a TrueNAS SCALE system goes (apps, ZFS ARC, VMs)
# and suggests settings for known memory-hungry apps. It changes NOTHING: it
# only reads `free`, ZFS arcstats, `docker inspect/stats` and `midclt` queries.
#
#   bash <(curl -fsSL https://raw.githubusercontent.com/Kevin2296/immich-toolbox/main/extras/truenas-memory-check.sh) [--lang nl|en]
#
# Environment variable VALUES are never printed (they may contain passwords);
# only whether a recommended setting is present.
set -Eeuo pipefail

LANG_CODE="nl"
while (($#)); do
  case "$1" in
    --lang) LANG_CODE="${2:-nl}"; shift;;
    --lang=*) LANG_CODE="${1#--lang=}";;
    -h|--help) sed -n '2,12p' "$0" 2>/dev/null || true; exit 0;;
    *) echo "Unknown option: $1" >&2; exit 1;;
  esac
  shift
done
[[ "$LANG_CODE" =~ ^(nl|en)$ ]] || LANG_CODE=en

for c in docker python3; do command -v "$c" >/dev/null 2>&1 || { echo "$c is missing" >&2; exit 1; }; done
[[ $EUID -eq 0 ]] && SUDO="" || SUDO="sudo"
[[ -z "$SUDO" ]] || $SUDO -v

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
free -b >"$TMP/free" 2>/dev/null || true
cat /proc/spl/kstat/zfs/arcstats >"$TMP/arc" 2>/dev/null || true
ids="$($SUDO docker ps -q 2>/dev/null || true)"
if [[ -n "$ids" ]]; then
  # shellcheck disable=SC2086
  $SUDO docker inspect $ids >"$TMP/inspect.json" 2>/dev/null || echo '[]' >"$TMP/inspect.json"
  # shellcheck disable=SC2086
  $SUDO docker stats --no-stream --format '{{.ID}}\t{{.MemUsage}}\t{{.CPUPerc}}' $ids >"$TMP/stats" 2>/dev/null || true
else
  echo '[]' >"$TMP/inspect.json"; : >"$TMP/stats"
fi
if command -v midclt >/dev/null 2>&1; then
  $SUDO midclt call vm.query >"$TMP/vms.json" 2>/dev/null || echo '[]' >"$TMP/vms.json"
  $SUDO midclt call vm.get_available_memory >"$TMP/vm_avail" 2>/dev/null || : >"$TMP/vm_avail"
else
  echo '[]' >"$TMP/vms.json"; : >"$TMP/vm_avail"
fi

python3 - "$TMP" "$LANG_CODE" <<'PY'
import json, os, re, sys
tmp, lang = sys.argv[1], sys.argv[2]
NL = lang == "nl"
def t(en, nl): return nl if NL else en
GiB = 1024 ** 3; MiB = 1024 ** 2
def fmt(b):
    return f"{b / GiB:.1f} GB" if b >= GiB else f"{b / MiB:.0f} MB"
def read(name):
    try:
        with open(os.path.join(tmp, name), encoding="utf-8", errors="replace") as f: return f.read()
    except OSError: return ""
def size(txt):
    m = re.match(r"\s*([\d.]+)\s*([KMGT]?i?B)", txt or "")
    if not m: return 0
    mult = {"B": 1, "KB": 1e3, "MB": 1e6, "GB": 1e9, "TB": 1e12, "KiB": 1024, "MiB": MiB, "GiB": GiB, "TiB": 1024 ** 4}
    return int(float(m.group(1)) * mult.get(m.group(2), 1))

B = "\033[1m"; Y = "\033[33m"; G = "\033[32m"; R = "\033[31m"; X = "\033[0m"
if not sys.stdout.isatty(): B = Y = G = R = X = ""
def head(s): print(f"\n{B}{s}{X}\n" + "─" * min(len(s), 70))

# ---- totals -------------------------------------------------------------------
mem = {}
for line in read("free").splitlines():
    p = line.split()
    if p and p[0] == "Mem:" and len(p) >= 7:
        mem = {"total": int(p[1]), "used": int(p[2]), "free": int(p[3]), "available": int(p[6])}
arc = {}
for line in read("arc").splitlines():
    p = line.split()
    if len(p) == 3 and p[0] in ("size", "c_min", "c_max"): arc[p[0]] = int(p[2])

# ---- containers ---------------------------------------------------------------
stats = {}
for line in read("stats").splitlines():
    p = line.split("\t")
    if len(p) >= 3:
        stats[p[0][:12]] = (size(p[1].split("/")[0]), float(p[2].strip().rstrip("%") or 0))
try: inspect = json.loads(read("inspect.json") or "[]")
except ValueError: inspect = []
total_ram = mem.get("total") or 0
containers = []
for c in inspect:
    cid = c.get("Id", "")[:12]
    labels = (c.get("Config") or {}).get("Labels") or {}
    project = labels.get("com.docker.compose.project", "")
    app = project[3:] if project.startswith("ix-") else (project or c.get("Name", "").lstrip("/"))
    env = {}
    for e in (c.get("Config") or {}).get("Env") or []:
        k, _, v = e.partition("="); env[k] = v
    hc = c.get("HostConfig") or {}
    st = c.get("State") or {}
    used, cpu = stats.get(cid, (0, 0.0))
    containers.append({
        "name": c.get("Name", "").lstrip("/"), "app": app, "service": labels.get("com.docker.compose.service", ""),
        "image": (c.get("Config") or {}).get("Image", ""), "env": env, "used": used, "cpu": cpu,
        "limit": hc.get("Memory") or 0, "restarts": c.get("RestartCount") or 0, "oom": bool(st.get("OOMKilled"))})

apps = {}
for c in containers:
    a = apps.setdefault(c["app"], {"used": 0, "cpu": 0.0, "containers": []})
    a["used"] += c["used"]; a["cpu"] += c["cpu"]; a["containers"].append(c)
apps_total = sum(a["used"] for a in apps.values())

# ---- overview -------------------------------------------------------------------
head(t("Memory overview", "Geheugenoverzicht"))
if mem:
    print(f"  {t('Installed (seen by Linux)', 'Geïnstalleerd (zichtbaar voor Linux)'):38} {fmt(mem['total'])}")
    print(f"  {t('Apps (all containers)', 'Apps (alle containers)'):38} {fmt(apps_total)}")
    if arc.get("size"):
        print(f"  {t('ZFS cache (ARC, given back when needed)', 'ZFS-cache (ARC, wordt teruggegeven)'):38} {fmt(arc['size'])}  (min {fmt(arc.get('c_min', 0))}, max {fmt(arc.get('c_max', 0))})")
        other = max(0, mem["used"] - apps_total - arc["size"])
        print(f"  {t('TrueNAS itself + other', 'TrueNAS zelf + overig'):38} ~{fmt(other)}")
    print(f"  {t('Free', 'Vrij'):38} {fmt(mem['free'])}")

# ---- VMs ---------------------------------------------------------------------------
try: vms = json.loads(read("vms.json") or "[]")
except ValueError: vms = []
avail_txt = read("vm_avail").strip()
vm_avail = int(avail_txt) if avail_txt.isdigit() else None
if vms:
    head(t("Virtual machines", "Virtuele machines"))
    if vm_avail is not None:
        print(f"  {t('Available for VMs now', 'Nu beschikbaar voor VM’s'):30} {fmt(vm_avail)}")
    for v in vms:
        need = int(v.get("memory") or 0) * MiB
        mn = int(v.get("min_memory") or 0) * MiB
        state = (v.get("status") or {}).get("state", "?")
        line = f"  {v.get('name', '?'):30} {fmt(need)}" + (f" (min {fmt(mn)})" if mn else "") + f"  [{state}]"
        if state != "RUNNING" and vm_avail is not None:
            start_need = mn or need
            if start_need > vm_avail: line += f"  {R}✗ {t('does not fit', 'past niet')}{X}"
            elif start_need > vm_avail - 1 * GiB: line += f"  {Y}! {t('fits barely', 'past maar net')}{X}"
            else: line += f"  {G}✓ {t('fits', 'past')}{X}"
        print(line)

# ---- per app ----------------------------------------------------------------------
head(t("Apps by memory use", "Apps op geheugengebruik"))
for name, a in sorted(apps.items(), key=lambda x: -x[1]["used"]):
    print(f"  {name:32} {fmt(a['used']):>9}   CPU {a['cpu']:5.1f}%")

# ---- advice -------------------------------------------------------------------------
tips, saving = [], 0
def has(env, key, pat=None):
    v = env.get(key)
    return v is not None and (pat is None or re.search(pat, v) is not None)
def tip(app, text, where, est=0):
    global saving
    tips.append((app, text, where)); saving += max(0, est)
ENVW = t("Apps → {a} → Edit → Additional Environment Variables", "Apps → {a} → Edit → Additional Environment Variables")
for c in containers:
    img, env, used, a = c["image"].lower(), c["env"], c["used"], c["app"]
    w = ENVW.format(a=a)
    if "elasticsearch" in img or re.search(r"(^|/)elastic", img):
        if not has(env, "ES_JAVA_OPTS", r"-Xmx"):
            # Elasticsearch 7.11+ sizes its heap to ~half of the container memory limit. Catalog apps often
            # have no env field for this inner container, so the app's memory limit is the usual lever.
            tip(a, f"{c['service'] or c['name']} ({t('runs inside this app', 'draait binnen deze app')}, {t('now', 'nu')} {fmt(used)}): "
                   + t("lower the app's memory limit to 2 GB (Elasticsearch uses about half of it), or add ES_JAVA_OPTS=-Xms512m -Xmx512m if the app has an environment field for it. Rarely used? Stop the app.",
                       "zet de geheugenlimiet van de app op 2 GB (Elasticsearch gebruikt daar ongeveer de helft van), of voeg ES_JAVA_OPTS=-Xms512m -Xmx512m toe als de app daar een veld voor heeft. Zelden gebruikt? Stop de app."),
                f"Apps → {a} → Edit → Resources", used - 1200 * MiB)
    elif "opensearch" in img:
        if not has(env, "OPENSEARCH_JAVA_OPTS", r"-Xmx"):
            tip(a, f"{c['service'] or c['name']}: OPENSEARCH_JAVA_OPTS=-Xms512m -Xmx512m  ({t('now', 'nu')} {fmt(used)})", w, used - 900 * MiB)
    elif "graylog/graylog" in img or re.search(r"(^|/)graylog(:|$)", img):
        if not has(env, "GRAYLOG_SERVER_JAVA_OPTS", r"-Xmx"):
            tip(a, f"{c['service'] or c['name']}: GRAYLOG_SERVER_JAVA_OPTS=-Xms512m -Xmx512m  ({t('now', 'nu')} {fmt(used)})", w, used - 700 * MiB)
    elif "paperless-ngx" in img and "postgres" not in img and "redis" not in img:
        missing = [k for k in ("PAPERLESS_TASK_WORKERS", "PAPERLESS_THREADS_PER_WORKER", "PAPERLESS_WEBSERVER_WORKERS") if k not in env]
        if missing:
            tip(a, f"{', '.join(k + '=1' for k in missing)}  ({t('lower peaks while processing documents; now', 'lagere pieken bij het verwerken; nu')} {fmt(used)})", w, used - 800 * MiB)
    elif "ollama" in img:
        if not has(env, "OLLAMA_KEEP_ALIVE"):
            tip(a, "OLLAMA_KEEP_ALIVE=1m  (" + t("unload the model 1 minute after use instead of 5; models can take several GB", "model na 1 minuut uit het geheugen i.p.v. 5; een model kan meerdere GB gebruiken") + ")", w, 0)
        if not c["limit"] or c["limit"] >= total_ram * 0.9:
            tip(a, t("set a memory limit that fits your model (e.g. 4–6 GB)", "zet een geheugenlimiet die bij je model past (bv. 4–6 GB)"), f"Apps → {a} → Edit → Resources", 0)
    elif re.search(r"(sonarr|radarr|prowlarr|lidarr|readarr|whisparr|bazarr-net)", img):
        if not has(env, "DOTNET_gcServer", r"^0$"):
            tip(a, f"DOTNET_gcServer=0  ({t('leaner .NET memory management; now', 'zuiniger .NET-geheugenbeheer; nu')} {fmt(used)})", w, min(80 * MiB, used // 4))
    elif "immich-pet-tagger" in img:
        if not has(env, "MALLOC_ARENA_MAX"):
            tip(a, t(f"Pet Tagger keeps ~1 GB after a scan (now {fmt(used)}): update the Immich Toolbox to v1.5.2 or newer (Update), or restart the container after a big scan",
                     f"Pet Tagger houdt na een scan ~1 GB vast (nu {fmt(used)}): update de Immich Toolbox naar v1.5.2 of nieuwer (optie 1 Update), of herstart de container na een grote scan"),
                "Immich Toolbox", max(0, used - 450 * MiB))
    if c["oom"]:
        tip(a, f"{R}{c['name']}: {t('was killed for using too much memory (OOM); its memory limit is too low', 'is gestopt wegens te veel geheugen (OOM); de geheugenlimiet is te laag')}{X}", f"Apps → {a} → Edit → Resources", 0)
    elif c["restarts"] >= 5:
        tip(a, f"{Y}{c['name']}: {c['restarts']} {t('restarts — check the logs', 'herstarts — bekijk de logs')}{X}", f"Apps → {a} → Logs", 0)

# duplicates by image (without tag)
by_image = {}
for c in containers:
    by_image.setdefault(c["image"].split("@")[0].rsplit(":", 1)[0], set()).add(c["app"])
for img, names in sorted(by_image.items()):
    if len(names) > 1 and re.search(r"(sonarr|radarr|prowlarr|lidarr|readarr|jellyfin|plex|immich-server)", img):
        tip(", ".join(sorted(names)), t(f"same app runs {len(names)}×  ({img}) — intended?", f"dezelfde app draait {len(names)}×  ({img}) — bewust?"), t("stop the one you do not use", "stop degene die je niet gebruikt"), 0)

head(t("Suggestions", "Tips"))
if not tips:
    print(f"  {G}✓ {t('Nothing to improve found.', 'Niets gevonden om te verbeteren.')}{X}")
for app, text, where in tips:
    print(f"  • {B}{app}{X}: {text}\n      → {where}")
if saving > 0:
    print(f"\n  {t('Estimated saving', 'Geschatte besparing')}: ~{fmt(saving)}")
print("\n  " + t("Notes: a memory limit (Resources) must stay above what an app really needs, or it crashes and restarts; for Java apps keep it at least 2× -Xmx. "
                 "Leave the ZFS cache alone: TrueNAS gives it back when apps or VMs need memory. Apps you rarely use can simply be stopped (Apps → Stop).",
                 "Let op: een geheugenlimiet (Resources) moet boven wat een app echt nodig heeft blijven, anders crasht en herstart hij; bij Java-apps minstens 2× -Xmx. "
                 "Laat de ZFS-cache met rust: TrueNAS geeft die terug als apps of VM’s geheugen nodig hebben. Apps die je zelden gebruikt kun je gewoon stoppen (Apps → Stop)."))
print("  " + t("This script changed nothing.", "Dit script heeft niets gewijzigd."))
PY
