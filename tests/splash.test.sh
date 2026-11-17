#!/usr/bin/env bash
# splash.py zonder Pi: een nagebootste framebuffer (een bestand) en de sysfs-gegevens ervan. Het logo staat in het
# midden, de randen hebben de achtergrondkleur van het logo, 32 en 16 bits per pixel (met een langere rij dan het beeld),
# en de tweede keer komt het scherm uit de cache. Zonder framebuffer: geen fout, geen logo.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
fail() { echo "FOUT: $*"; exit 1; }
fb() {  # breedte hoogte bpp stride
  rm -rf "$T/sys" "$T/cache"; mkdir -p "$T/sys"
  echo "$1,$2" > "$T/sys/virtual_size"; echo "$3" > "$T/sys/bits_per_pixel"; echo "$4" > "$T/sys/stride"
  head -c $(( $4 * $2 )) /dev/zero > "$T/fb"
}
run() { EVX_PI_FB="$T/fb" EVX_PI_FB_SYSFS="$T/sys" EVX_PI_SPLASH_CACHE="$T/cache" EVX_PI_TTY= EVX_PI_FB_WAIT=1 python3 "$ROOT/pi/splash.py"; }
check() {  # bpp stride breedte hoogte
  python3 - "$T/fb" "$@" <<'PY'
import sys
data = open(sys.argv[1], 'rb').read()
bpp, stride, w, h = (int(x) for x in sys.argv[2:])
size = bpp // 8
def at(x, y): return data[y * stride + x * size:y * stride + x * size + size]
import struct
r, g, b = 0x12, 0x10, 0x1a  # de achtergrondkleur van het logo (in de TGA als B, G, R: 1a 10 12)
bg = {32: bytes((b, g, r, 0)), 16: struct.pack('<H', (r >> 3) << 11 | (g >> 2) << 5 | b >> 3)}[bpp]
assert len(data) == stride * h, len(data)
assert at(0, 0) == bg and at(w - 1, h - 1) == bg, (at(0, 0).hex(), bg.hex())
other = sum(1 for y in range(0, h, 7) for x in range(0, w, 7) if at(x, y) != bg)
assert other > 50, f'geen logo: {other}'
PY
}
fb 1920 1080 32 7680
start=$(date +%s%N); run; first=$(( ($(date +%s%N) - start) / 1000000 ))
check 32 7680 1920 1080 || fail "32 bits: logo of achtergrond klopt niet"
ls "$T/cache"/splash-1920x1080-32-*.raw >/dev/null || fail "geen cache"
head -c $(( 7680 * 1080 )) /dev/zero > "$T/fb"
start=$(date +%s%N); run; again=$(( ($(date +%s%N) - start) / 1000000 ))
check 32 7680 1920 1080 || fail "32 bits uit de cache klopt niet"
echo "ok   1920x1080, 32 bits: logo in het midden, rand in de achtergrondkleur (${first} ms, uit de cache ${again} ms)"
fb 800 480 16 1664
run; check 16 1664 800 480 || fail "16 bits klopt niet"
echo "ok   800x480, 16 bits met een langere rij: logo en achtergrond"
rm -rf "$T/sys"; out="$(EVX_PI_FB="$T/geen" EVX_PI_FB_SYSFS="$T/sys" EVX_PI_TTY= EVX_PI_FB_WAIT=0.3 python3 "$ROOT/pi/splash.py")"
[ "$out" = "Geen framebuffer: geen logo" ] || fail "zonder framebuffer: $out"
echo "ok   geen framebuffer: geen fout, geen logo"

# Voortgang (--progress): een balk onder het logo, deels gevuld naar de vorige opstartduur; zodra labwc draait vol, en de
# nieuwe duur bewaard
fb 1920 1080 32 7680
run
mkdir -p "$T/proc" "$T/cache"; echo "10.0 20.0" > "$T/proc/uptime"; echo 20 > "$T/cache/boot-seconds"
EVX_PI_FB="$T/fb" EVX_PI_FB_SYSFS="$T/sys" EVX_PI_SPLASH_CACHE="$T/cache" EVX_PI_PROC="$T/proc" EVX_PI_PROGRESS_TICK=0.05 \
  python3 "$ROOT/pi/splash.py" --progress &
PID=$!
sleep 0.6
bar() {  # aantal oranje pixels in de balk
  python3 - "$T/fb" <<'PY'
import sys
d = open(sys.argv[1], 'rb').read()
stride = 7680
orange = bytes((0x00, 0x6a, 0xff, 0))
print(max(sum(1 for x in range(1920) if d[y * stride + x * 4:y * stride + x * 4 + 4] == orange) for y in range(1080)))
PY
}
half="$(bar)"
[ "$half" -gt 200 ] && [ "$half" -lt 400 ] || fail "balk na 10 van 20 s: $half oranje pixels (verwacht ~288 van 576)"
mkdir -p "$T/proc/321"; echo labwc > "$T/proc/321/comm"
wait "$PID"
[ "$(bar)" -ge 570 ] || fail "balk niet vol toen labwc er was: $(bar)"
[ "$(cat "$T/cache/boot-seconds")" = "10.0" ] || fail "opstartduur niet bewaard: $(cat "$T/cache/boot-seconds")"
echo "ok   voortgang: balk naar de vorige opstartduur ($half van 576), vol zodra de kiosk er is, nieuwe duur bewaard"
