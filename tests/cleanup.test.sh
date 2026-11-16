#!/usr/bin/env bash
# cleanup.sh zonder Pi: in een nagebootste map ruimt hij crashdumps, crashrapporten van Chromium, oude tijdelijke
# bestanden, oude gedraaide logboeken en een te lang eerste-start-logboek op, en laat de rest (het Chromium-profiel met
# de koppeling, nieuwe bestanden) staan. apt en journalctl worden in deze modus niet aangeroepen.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
R="$T/root"; H=/home/kiosk; P="$R$H/.config/eventvox-kiosk"
mkdir -p "$R/var/crash" "$R/tmp" "$R/var/tmp" "$R/var/log" "$P/Crash Reports/pending" "$P/Default/Local Storage"
touch "$R/var/crash/core.1" "$P/Crash Reports/pending/a.dmp" "$P/Default/Local Storage/token" "$R/tmp/nieuw" "$R/var/log/syslog"
touch -d '10 days ago' "$R/tmp/oud" "$R/var/tmp/oud"
touch -d '20 days ago' "$R/var/log/syslog.2.gz" "$R/var/log/messages.1"
seq 1 3000 > "$R/var/log/eventvox-pi-firstboot.log"
fail() { echo "FOUT: $*"; exit 1; }
OUT="$(EVX_PI_ROOT="$R" EVX_PI_STATE="$T/state" KIOSK_HOME="$H" bash "$ROOT/pi/cleanup.sh")"
for f in var/crash/core.1 tmp/oud var/tmp/oud var/log/syslog.2.gz var/log/messages.1; do
  [ -e "$R/$f" ] && fail "$f niet opgeruimd"
done
[ -e "$P/Crash Reports/pending/a.dmp" ] && fail "crashrapport van Chromium niet opgeruimd"
for f in "$P/Default/Local Storage/token" "$R/tmp/nieuw" "$R/var/log/syslog"; do
  [ -e "$f" ] || fail "$f had moeten blijven"
done
[ "$(wc -l < "$R/var/log/eventvox-pi-firstboot.log")" = 1000 ] || fail "eerste-start-logboek niet ingekort"
[ "$(tail -n1 "$R/var/log/eventvox-pi-firstboot.log")" = 3000 ] || fail "eerste-start-logboek: niet de laatste regels"
python3 -c 'import json,sys; o=json.load(open(sys.argv[1])); assert o["result"].startswith("Opgeruimd") and isinstance(o["freed_mb"], int) and o["at"] > 0, o' "$T/state/cleanup-result.json"
echo "ok   opruimen: crashdumps, oude tijdelijke bestanden en logboeken weg; profiel en nieuwe bestanden blijven ($OUT)"
