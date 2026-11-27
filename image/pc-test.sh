#!/bin/bash
# Proef op een nagebootste pc (QEMU x86-64, met KVM als dat er is): een kale Debian 13 (generic cloud image), install.sh
# uit deze checkout, herstart, en dan controleren of de kiosk echt draait:
#   - Chromium opent het adres met het serienummer uit het BIOS (QEMU -smbios, zoals een Dell OptiPlex);
#   - de agent zet window.WebKiosk in de pagina, met dat serienummer en het model "Dell Inc. OptiPlex 3060";
#   - de naam van de pc is eventvox-<laatste 8 tekens>, automatisch inloggen + labwc + Chromium staan op het scherm.
# De pagina is een eigen testpagina (http://10.0.2.2:8099/scanterminal/, op deze machine): die stuurt wat WebKiosk geeft
# terug. Schermafbeelding (screen.png), seriële console (serial.log) en het verslag (report.json) komen in <uitvoermap>.
#   image/pc-test.sh [uitvoermap]
# Nodig: qemu-system-x86_64, qemu-img, genisoimage, curl, python3 (en internet: Debian-image en apt in de pc).
# Wat dit niet test: echte hardware (geluid, wifi, NFC-lezer, een echt BIOS); dat blijft op een echte pc.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$(mkdir -p "${1:-pc-test-out}" && cd "${1:-pc-test-out}" && pwd)"
W="$(mktemp -d)"
TIMEOUT_S="${PC_TEST_TIMEOUT:-2700}"
IMAGE_URL="${DEBIAN_IMAGE:-https://cloud.debian.org/images/cloud/trixie/latest/debian-13-generic-amd64.qcow2}"
PORT=8099
SERIAL=EVXPC7Q2K9
QEMU_PID=""
SERVER_PID=""
cleanup() {
  [ -n "$QEMU_PID" ] && kill "$QEMU_PID" 2>/dev/null
  [ -n "$SERVER_PID" ] && kill "$SERVER_PID" 2>/dev/null
  rm -rf "$W"
}
trap cleanup EXIT
fail() {
  echo "FOUT: $*" >&2
  shot
  if [ -f "$OUT/serial.log" ]; then
    echo "--- laatste regels van de seriële console:" >&2
    tail -n 80 "$OUT/serial.log" >&2
  fi
  exit 1
}
shot() {
  [ -S "$W/monitor" ] || return 0
  python3 - "$W/monitor" "$OUT/screen.png" <<'PY' || true
import socket, sys, time
s = socket.socket(socket.AF_UNIX)
s.connect(sys.argv[1])
s.sendall(('screendump %s -f png\n' % sys.argv[2]).encode())
time.sleep(2)
s.close()
PY
  [ -s "$OUT/screen.png" ] && echo "    schermafbeelding: $OUT/screen.png"
}

echo "==> Debian 13 downloaden"
curl -fsSL -o "$W/base.qcow2" "$IMAGE_URL" || fail "Debian-image niet te downloaden ($IMAGE_URL)"
qemu-img create -q -f qcow2 -F qcow2 -b "$W/base.qcow2" "$W/disk.qcow2" 10G || fail "schijf maken"

echo "==> Testpagina op poort $PORT (in de pc: http://10.0.2.2:$PORT/scanterminal/)"
cat > "$W/server.py" <<'PY'
import http.server, json, sys
OUT = sys.argv[2]
PAGE = b'''<!doctype html><meta charset="utf-8"><title>EventVOX-Pi pc-test</title>
<body style="margin:0;background:#0b3d5c;color:#fff;font:32px sans-serif;display:flex;align-items:center;justify-content:center;height:100vh;text-align:center">
<div><div style="font-size:56px;font-weight:bold">EventVOX-Pi op een pc</div><div id="s" style="margin-top:24px">wacht op WebKiosk...</div></div>
<script>
function send() {
  if (!window.WebKiosk || !WebKiosk.getSerial()) { setTimeout(send, 1000); return; }
  var r = { url: location.href, serial: WebKiosk.getSerial(), info: JSON.parse(WebKiosk.getDeviceInfo()),
            status: JSON.parse(WebKiosk.getStatus()), network: JSON.parse(WebKiosk.getNetwork() || 'null') };
  document.getElementById('s').textContent = r.serial + ' - ' + (r.info.model || '?');
  fetch('/report', { method: 'POST', body: JSON.stringify(r) });
  setTimeout(send, 10000);
}
send();
</script>'''
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-Type', 'text/html; charset=utf-8')
        self.end_headers()
        self.wfile.write(PAGE)
        with open(OUT + '/requests.log', 'a') as f:
            f.write(self.path + '\n')
    def do_POST(self):
        body = self.rfile.read(int(self.headers.get('Content-Length', 0)))
        with open(OUT + '/report.json', 'wb') as f:
            f.write(body)
        self.send_response(204)
        self.end_headers()
    def log_message(self, *a):
        pass
http.server.ThreadingHTTPServer(('127.0.0.1', int(sys.argv[1])), H).serve_forever()
PY
python3 "$W/server.py" "$PORT" "$OUT" &
SERVER_PID=$!

echo "==> Inrichting via cloud-init: gebruiker kiosk (uid 1000, zoals de Debian-installatie), install.sh, herstart"
mkdir -p "$W/seed"
tar -czf "$W/seed/kit.tar.gz" -C "$ROOT" install.sh pi
cat > "$W/seed/meta-data" <<EOF
instance-id: evx-pc-test
local-hostname: debian
EOF
cat > "$W/seed/user-data" <<EOF
#cloud-config
users:
  - name: kiosk
    shell: /bin/bash
    lock_passwd: true
    sudo: ALL=(ALL) NOPASSWD:ALL
write_files:
  - path: /usr/local/sbin/evx-pc-test-report
    permissions: '0755'
    content: |
      #!/bin/bash
      # Na het starten: wat er draait naar de seriële console (de test leest serial.log)
      sleep 120
      {
        echo "=== EVX-PC-TEST naam: \$(hostname)"
        echo "=== EVX-PC-TEST serial: \$(cat /var/lib/eventvox-pi/serial 2>/dev/null)"
        echo "=== EVX-PC-TEST processen:"; ps -eo user,comm | grep -E 'labwc|chrom|python3|seatd|agetty' | sort | uniq -c
        echo "=== EVX-PC-TEST agent:"; journalctl -b --no-pager -q _SYSTEMD_USER_UNIT=eventvox-pi-agent.service | tail -n 20
        echo "=== EVX-PC-TEST labwc/kiosk:"; journalctl -b --no-pager -q _UID=1000 | grep -v eventvox-pi-agent | tail -n 30
        echo "=== EVX-PC-TEST einde"
      } > /dev/ttyS0 2>&1
  - path: /etc/systemd/system/evx-pc-test-report.service
    content: |
      [Unit]
      Description=pc-test: verslag naar de seriële console
      After=multi-user.target
      [Service]
      Type=oneshot
      ExecStart=/usr/local/sbin/evx-pc-test-report
      [Install]
      WantedBy=multi-user.target
runcmd:
  - [ bash, -c, 'set -e; mkdir -p /mnt/seed /root/kit; mount -o ro /dev/sr0 /mnt/seed; tar -xzf /mnt/seed/kit.tar.gz -C /root/kit; echo "=== EVX-PC-TEST install.sh begint" > /dev/ttyS0; if URL="http://10.0.2.2:$PORT/scanterminal/?serial={serial}" bash -x /root/kit/install.sh > /root/install.log 2>&1; then echo "=== EVX-PC-TEST install.sh klaar" > /dev/ttyS0; else tail -n 60 /root/install.log | while IFS= read -r l; do echo "EVX-LOG: \$l"; done > /dev/ttyS0; echo "=== EVX-PC-TEST install.sh MISLUKT" > /dev/ttyS0; fi; echo "PAGE_MATCH=^http://10\\.0\\.2\\.2:$PORT/scanterminal" >> /etc/eventvox-pi/config; systemctl enable evx-pc-test-report.service; sync; systemctl reboot' ]
EOF
cp "$W/seed/user-data" "$OUT/user-data.yaml"   # ter controle bij een fout
genisoimage -quiet -o "$W/seed.iso" -V cidata -J -r "$W/seed" || fail "seed-ISO maken"

ACCEL=tcg
[ -w /dev/kvm ] && ACCEL=kvm
echo "==> De pc starten (QEMU, $ACCEL; Dell OptiPlex 3060 met serienummer $SERIAL in het BIOS)"
qemu-system-x86_64 -machine q35,accel="$ACCEL" -cpu max -smp 2 -m 3072 \
  -smbios "type=1,manufacturer=Dell Inc.,product=OptiPlex 3060,serial=$SERIAL" \
  -drive file="$W/disk.qcow2",if=virtio -cdrom "$W/seed.iso" \
  -netdev user,id=n0 -device virtio-net-pci,netdev=n0 \
  -device virtio-vga -display none -monitor unix:"$W/monitor",server,nowait \
  -serial file:"$OUT/serial.log" &
QEMU_PID=$!

echo "==> Wachten op het verslag van de pagina (hoogstens $((TIMEOUT_S / 60)) min)"
START=$(date +%s)
LAST=""
while [ ! -s "$OUT/report.json" ]; do
  kill -0 "$QEMU_PID" 2>/dev/null || fail "QEMU is gestopt"
  [ $(( $(date +%s) - START )) -gt "$TIMEOUT_S" ] && fail "geen verslag van de pagina binnen $((TIMEOUT_S / 60)) min"
  NOW="$(grep -ao '=== EVX-PC-TEST install.sh [A-Za-z]*' "$OUT/serial.log" 2>/dev/null | tail -1)"
  [ -n "$NOW" ] && [ "$NOW" != "$LAST" ] && { echo "    $(( ($(date +%s) - START) / 60 )) min: ${NOW#=== EVX-PC-TEST }"; LAST="$NOW"; }
  if grep -aq 'EVX-PC-TEST install.sh MISLUKT' "$OUT/serial.log" 2>/dev/null; then
    # De laatste regels van install.sh (bash -x), los van de meldingen van systemd op dezelfde console
    echo "--- laatste regels van install.sh:" >&2
    grep -a '^EVX-LOG: ' "$OUT/serial.log" | sed 's/^EVX-LOG: //' | tr -d '\r' >&2
    fail "install.sh mislukt"
  fi
  sleep 10
done
echo "    verslag na $(( ($(date +%s) - START) / 60 )) min"
sleep 15
shot
# Het verslag van evx-pc-test-report (2 minuten na het starten) nog even afwachten
for _ in $(seq 1 18); do grep -aq 'EVX-PC-TEST einde' "$OUT/serial.log" && break; sleep 10; done
sed -n '/=== EVX-PC-TEST naam/,/=== EVX-PC-TEST einde/p' "$OUT/serial.log" | tr -d '\r'

echo "==> Controleren"
python3 - "$OUT/report.json" "$SERIAL" "$OUT/serial.log" <<'PY' || fail "controle"
import json, re, sys
r = json.load(open(sys.argv[1]))
serial = sys.argv[2]
log = open(sys.argv[3], 'rb').read().decode('utf-8', 'replace')
problems = []
def check(ok, text):
    print(('ok   ' if ok else 'FOUT ') + text)
    if not ok:
        problems.append(text)
check(('serial=' + serial) in r.get('url', ''), 'Chromium opent het adres met het serienummer uit het BIOS (%s)' % r.get('url'))
check(r.get('serial') == serial, 'WebKiosk.getSerial() = %s' % r.get('serial'))
check(r.get('info', {}).get('model') == 'Dell Inc. OptiPlex 3060', 'getDeviceInfo().model = %s' % r.get('info', {}).get('model'))
check(r.get('status', {}).get('app') == 'pi', "getStatus().app = 'pi' (EventVOX-Pi)")
check((r.get('status', {}).get('pi') or {}).get('model') == 'Dell Inc. OptiPlex 3060', 'getStatus().pi.model = het model uit het BIOS')
check('undervoltage' not in (r.get('status', {}).get('pi') or {}), 'geen onderspanning op een pc (alleen een Pi meet dat)')
m = re.search(r'=== EVX-PC-TEST naam: (\S+)', log)
check(bool(m) and m.group(1) == 'eventvox-' + serial.lower()[-8:], 'naam van de pc: %s' % (m.group(1) if m else '?'))
check('install.sh klaar' in log, 'install.sh liep zonder fout')
print()
print('Verslag van de pagina:', json.dumps(r, indent=1)[:1500])
sys.exit(1 if problems else 0)
PY
echo "==> Klaar: EventVOX-Pi draait op de nagebootste pc"
