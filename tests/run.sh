#!/usr/bin/env bash
# Alle controles die zonder Pi kunnen (lokaal en in CI): scripts, Python en de agent tegen Chromium.
# Met FRONTEND=/pad/naar/eventvox-frontend ook tegen de echte scanterminal.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
echo "== Scripts"
for f in "$ROOT/install.sh" "$ROOT"/pi/*.sh "$ROOT/pi/eventvox-pi-root" "$ROOT"/image/*.sh; do bash -n "$f"; done
if command -v shellcheck >/dev/null; then
  shellcheck -S warning "$ROOT/install.sh" "$ROOT"/pi/*.sh "$ROOT/pi/eventvox-pi-root" "$ROOT"/image/*.sh
else
  echo "(shellcheck niet geïnstalleerd: overgeslagen)"
fi
echo "== Python"
python3 -m py_compile "$ROOT/pi/agent.py" "$ROOT/pi/wifi.py" "$ROOT/pi/ssh.py"
node --check "$ROOT/pi/bridge.js"
node --check "$ROOT/pi/locate.js"
echo "== Imager-beschrijving (image/manifest.py)"
T="$(mktemp -d)"
printf 'fake' > "$T/x.img.xz"
echo "123 abc" > "$T/x.extract"
echo '{"name":"Raspberry Pi OS Lite (64-bit)","icon":"https://x/icon.png","devices":["pi3-64bit"],"init_format":"cloudinit-rpi","capabilities":["rpi_connect"],"architecture":"armv8"}' > "$T/base.json"
python3 "$ROOT/image/manifest.py" "$T/base.json" 1.2.3 "$T/x.img.xz" "$T/x.extract" https://example/x.img.xz > "$T/m.json"
python3 - "$T/m.json" <<'PY'
import json, sys
e = json.load(open(sys.argv[1]))['os_list'][0]
assert e['init_format'] == 'cloudinit-rpi' and e['capabilities'] == ['rpi_connect'] and e['devices'] == ['pi3-64bit'], e
assert e['extract_size'] == 123 and e['image_download_size'] == 4 and len(e['image_download_sha256']) == 64, e
print('ok   init_format, capabilities en devices van het basis-image, groottes en SHA-256')
PY
rm -rf "$T"
echo "== Bijwerken (update.sh)"
bash "$ROOT/tests/update.test.sh"
echo "== Wifi (wifi.py)"
bash "$ROOT/tests/wifi.test.sh"
echo "== SSH-sleutels (ssh.py)"
bash "$ROOT/tests/ssh.test.sh"
echo "== Agent tegen Chromium"
node --test "$ROOT/tests/agent.test.mjs"
