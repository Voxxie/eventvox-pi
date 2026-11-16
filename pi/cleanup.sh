#!/bin/bash
# EventVOX-Pi: wekelijks onderhoud (als root, eventvox-pi-cleanup.timer). Ruimt op wat op een kiosk vanzelf groeit:
# apt-downloads en oude pakketten, het systeemlogboek boven de grens, crashdumps, oude tijdelijke bestanden en het
# eerste-start-logboek. Raakt nooit de opstart (config.txt, cmdline.txt, initramfs), de instellingen of de koppeling
# met EventVOX (het Chromium-profiel behalve crashrapporten). Uitkomst in $STATE/cleanup-result.json.
STATE="${EVX_PI_STATE:-/var/lib/eventvox-pi}"
ROOTDIR="${EVX_PI_ROOT:-}"          # alleen voor de tests: alles onder deze map
KIOSK_HOME="${KIOSK_HOME:-$(getent passwd 1000 | cut -d: -f6)}"

free_mb() { df -Pm "${ROOTDIR:-/}" | awk 'NR==2 {print $4}'; }
BEFORE="$(free_mb)"
DONE=()

if [ -z "$ROOTDIR" ]; then
  DEBIAN_FRONTEND=noninteractive apt-get -y -q autoremove --purge >/dev/null 2>&1 && DONE+=("oude pakketten")
  apt-get clean >/dev/null 2>&1 && DONE+=("apt-downloads")
  journalctl --vacuum-size=50M --vacuum-time=2weeks >/dev/null 2>&1 && DONE+=("systeemlogboek")
fi
# Crashdumps en oude tijdelijke bestanden (ouder dan 7 dagen)
find "$ROOTDIR/var/crash" -mindepth 1 -delete 2>/dev/null
if [ -n "$KIOSK_HOME" ] && [ -d "$ROOTDIR$KIOSK_HOME/.config/eventvox-kiosk" ]; then
  find "$ROOTDIR$KIOSK_HOME/.config/eventvox-kiosk" -path '*Crash Reports*' -type f -delete 2>/dev/null
fi
find "$ROOTDIR/tmp" "$ROOTDIR/var/tmp" -mindepth 1 -type f -mtime +7 -delete 2>/dev/null
DONE+=("crashdumps en oude tijdelijke bestanden")
# Logboeken die niet via het systeemlogboek gaan: alleen de laatste 1000 regels
f="$ROOTDIR/var/log/eventvox-pi-firstboot.log"
if [ -f "$f" ] && [ "$(wc -l < "$f")" -gt 1000 ]; then
  tail -n 1000 "$f" > "$f.tmp" && cat "$f.tmp" > "$f"
  rm -f "$f.tmp"
fi
find "$ROOTDIR/var/log" -type f \( -name '*.gz' -o -name '*.[0-9]' \) -mtime +14 -delete 2>/dev/null

AFTER="$(free_mb)"
FREED=$(( AFTER - BEFORE )); [ "$FREED" -lt 0 ] && FREED=0
RESULT="Opgeruimd: $(IFS=,; echo "${DONE[*]}" | sed 's/,/, /g'); ${FREED} MB vrijgemaakt, ${AFTER} MB vrij"
mkdir -p "$STATE"
python3 - "$STATE/cleanup-result.json" "$RESULT" "$FREED" <<'PY'
import json, sys, time
json.dump({'at': int(time.time()), 'result': sys.argv[2], 'freed_mb': int(sys.argv[3])}, open(sys.argv[1], 'w'))
PY
echo "$RESULT"
