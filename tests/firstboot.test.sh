#!/usr/bin/env bash
# image/firstboot.sh zonder Pi: met een nagebootste install.sh die stappen meldt. Op het "scherm" (een bestand in plaats
# van /dev/tty1) staan de stappen met nummer en de tijd; bij succes "ingericht", bij een fout de stap waar het misging.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/kit" "$T/bin"
printf '#!/bin/bash\n[ "$1" = passwd ] && [ "$2" = 1000 ] && echo "kiosk:x:1000:1000::/home/kiosk:/bin/bash"\n' > "$T/bin/getent"
chmod +x "$T/bin/getent"
kit() { printf '#!/bin/bash\nstep() { echo "==> $*"; }\nstep "Pakketten"\nsleep 6\nstep "Chromium-policy"\necho uitvoer\nstep "Raspberry Pi Connect"\nexit %s\n' "$1" > "$T/kit/install.sh"; }
run() { : > "$T/tty"; PATH="$T/bin:$PATH" EVX_FIRSTBOOT_LOG="$T/log" EVX_FIRSTBOOT_TTY="$T/tty" EVX_FIRSTBOOT_KIT="$T/kit" \
  EVX_FIRSTBOOT_DRYRUN=1 timeout 60 bash "$ROOT/image/firstboot.sh"; }
fail() { echo "FOUT: $*"; echo "--- scherm:"; cat "$T/tty"; echo; echo "--- log:"; cat "$T/log"; exit 1; }

kit 0; run
grep -q "stap 1 van ongeveer 3, Pakketten" "$T/tty" || fail "stap 1 niet op het scherm"
grep -q "min bezig" "$T/tty" || fail "geen tijd op het scherm"
grep -q "is ingericht" "$T/tty" || fail "geen 'ingericht' op het scherm"
grep -q "uitvoer" "$T/log" && grep -q "== klaar" "$T/log" || fail "logboek onvolledig"
echo "ok   eerste start: stappen met nummer en tijd op het scherm, daarna 'ingericht'"

kit 1; run
grep -q "Inrichten mislukt bij: Raspberry Pi Connect" "$T/tty" || fail "fout niet op het scherm"
grep -q "install.sh mislukt" "$T/log" || fail "fout niet in het logboek"
echo "ok   eerste start mislukt: de stap waar het misging op het scherm"
