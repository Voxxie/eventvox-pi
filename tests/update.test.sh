#!/usr/bin/env bash
# update.sh zonder Pi: een nieuwer pakket wordt gedownload, gecontroleerd (SHA-256) en geïnstalleerd, daarna een
# herstart; een pakket met een verkeerde SHA-256 niet; dezelfde versie: "Actueel". apt-get, dpkg-query en systemctl
# zijn nagebootst (PATH), het pakket staat lokaal (file://).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/state" "$T/opt" "$T/pkg/eventvox-pi"
for c in apt-get dpkg-query pkill; do printf '#!/bin/bash\necho "%s $*" >> "%s/calls"\n' "$c" "$T" > "$T/bin/$c"; done
printf '#!/bin/bash\necho "systemctl $*" >> "%s/calls"\n' "$T" > "$T/bin/systemctl"
chmod +x "$T/bin/"*
echo 10000 > "$T/opt/VERSION_CODE"; echo 1.0.0 > "$T/opt/VERSION"
# Het "nieuwe" pakket: een install.sh die alleen meldt dat hij draaide
printf '#!/bin/bash\necho "install $*" >> "%s/calls"\n' "$T" > "$T/pkg/eventvox-pi/install.sh"
(cd "$T/pkg" && tar -czf "$T/kit.tar.gz" eventvox-pi)
index() { printf '{"versionCode":%s,"versionName":"%s","url":"file://%s/kit.tar.gz","sha256":"%s","notes":""}' "$1" "$2" "$T" "$3" > "$T/update.json"; }
run() { : > "$T/calls"; PATH="$T/bin:$PATH" EVX_PI_STATE="$T/state" EVX_PI_OPT="$T/opt" EVX_PI_CONFIG=/dev/null UPDATE_INDEX="file://$T/update.json" bash "$ROOT/pi/update.sh" "$@" >/dev/null; }
result() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["result"])' "$T/state/update-result.json"; }
fail() { echo "FOUT: $*"; cat "$T/calls"; exit 1; }

index 10001 1.0.1 "$(sha256sum "$T/kit.tar.gz" | cut -d' ' -f1)"
run
grep -q "install --update" "$T/calls" || fail "nieuwere versie niet geïnstalleerd"
grep -q "systemctl reboot" "$T/calls" || fail "geen herstart na bijwerken"
result | grep -q "EventVOX-Pi 1.0.1" || fail "uitkomst: $(result)"
echo "ok   nieuwere versie: installeren en herstarten ($(result))"

index 10002 1.0.2 "0000000000000000000000000000000000000000000000000000000000000000"
run
grep -q "install" "$T/calls" && fail "pakket met verkeerde SHA-256 geïnstalleerd"
result | grep -q "mislukt" || fail "uitkomst: $(result)"
echo "ok   verkeerde SHA-256: niet installeren ($(result))"

index 10000 1.0.0 "$(sha256sum "$T/kit.tar.gz" | cut -d' ' -f1)"
run
grep -q "install\|reboot" "$T/calls" && fail "dezelfde versie toch geïnstalleerd of herstart"
result | grep -q "Actueel (1.0.0)" || fail "uitkomst: $(result)"
echo "ok   zelfde versie: actueel, geen herstart"

# Alleen EventVOX-Pi ("EventVOX-Pi bijwerken"): geen apt, geen herstart van de Pi, wel de agent en de browser opnieuw
index 10003 1.0.3 "$(sha256sum "$T/kit.tar.gz" | cut -d' ' -f1)"
run app
grep -q "install --update" "$T/calls" || fail "app: nieuwere versie niet geïnstalleerd"
grep -q "apt-get" "$T/calls" && fail "app: toch apt (Raspberry Pi OS) bijgewerkt"
grep -q "systemctl reboot" "$T/calls" && fail "app: toch de Pi herstart"
grep -q "restart eventvox-pi-agent.service" "$T/calls" || fail "app: agent niet herstart"
grep -q "pkill" "$T/calls" || fail "app: browser niet herstart"
[ -f "$T/state/restart-requested" ] || fail "app: browserherstart telt als crash (geen restart-requested)"
result | grep -q "EventVOX-Pi 1.0.3; de browser herstart" || fail "uitkomst: $(result)"
echo "ok   alleen EventVOX-Pi: installeren, agent en browser opnieuw, geen apt en geen herstart ($(result))"
echo 10003 > "$T/opt/VERSION_CODE"; echo 1.0.3 > "$T/opt/VERSION"
run app
grep -q "install\|apt-get\|reboot\|pkill" "$T/calls" && fail "app, zelfde versie: toch iets gedaan"
result | grep -q "Actueel (1.0.3)" || fail "uitkomst: $(result)"
echo "ok   alleen EventVOX-Pi, zelfde versie: actueel, niets gedaan"
