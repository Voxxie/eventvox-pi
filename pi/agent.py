#!/usr/bin/env python3
"""
EventVOX-Pi agent: maakt van een Raspberry Pi met Chromium een terminal die EventVOX kan zien en bedienen, net als de
kiosk-app EventVOX-Webkiosk op een Zebra.

Chromium draait met een debugpoort op 127.0.0.1 (kiosk.sh). De agent verbindt daarmee (Chrome DevTools Protocol, een
websocket) en zet in de scanterminal `window.WebKiosk` (bridge.js). De scanterminal geeft daarmee bij elke heartbeat de
staat van de Pi mee (`kiosk_status`: versie, wifi, temperatuur, onderspanning, ...) en geeft opdrachten en instellingen
uit EventVOX door (herladen, browser herstarten, Pi herstarten, bijwerken, Zoek mij).

Alleen de standaardbibliotheek van Python 3, geen extra pakketten. Draait als de kiosk-gebruiker (systemd --user);
herstarten en bijwerken gaan via sudo naar /usr/local/sbin/eventvox-pi-root (alleen die twee opdrachten).

Omgeving (voor tests): EVX_PI_CDP (standaard http://127.0.0.1:9222), EVX_PI_STATE (map met de staat, standaard
/var/lib/eventvox-pi), EVX_PI_HOME (de map met bridge.js, standaard de map van dit script), EVX_PI_DRYRUN=1 (herstarten
en bijwerken alleen in het logboek), EVX_PI_TICK (seconden tussen twee rondes, standaard 5).
"""
import base64
import collections
import datetime
import json
import os
import re
import socket
import struct
import subprocess
import sys
import threading
import time
import urllib.parse
import urllib.request

HOME = os.environ.get('EVX_PI_HOME') or os.path.dirname(os.path.abspath(__file__))
STATE_DIR = os.environ.get('EVX_PI_STATE', '/var/lib/eventvox-pi')
CDP = os.environ.get('EVX_PI_CDP', 'http://127.0.0.1:9222')
DRYRUN = os.environ.get('EVX_PI_DRYRUN') == '1'
TICK = float(os.environ.get('EVX_PI_TICK', '5'))
# Tests: een bestand waarin regels met NFC-nummers verschijnen (in plaats van een echte lezer), en een nagebootst
# systemctl (of het bijwerken loopt)
NFC_FAKE = os.environ.get('EVX_PI_NFC_FAKE')
SYSTEMCTL = os.environ.get('EVX_PI_SYSTEMCTL') or 'systemctl'
# Zo lang loopt het bijwerken: een eenmalige dienst (Type=oneshot) is "activating" zolang hij bezig is, niet "active"
UPDATE_BUSY = {'active', 'activating', 'reloading', 'deactivating'}
# Raspberry Pi Connect (als de kiosk-gebruiker, geen root nodig). Tests: EVX_PI_RPI_CONNECT = een nagebootst rpi-connect
RPI_CONNECT = os.environ.get('EVX_PI_RPI_CONNECT') or 'rpi-connect'
CONNECT_VERIFY = re.compile(r'https://connect\.raspberrypi\.com/verify/[A-Za-z0-9-]+')
CONNECT_WAIT_S = 15 * 60   # zo lang wacht de agent tot iemand de koppellink goedkeurt
MAINTENANCE_UPDATE = 'De terminal wordt bijgewerkt. Even geduld: hij start daarna vanzelf weer.'
MAINTENANCE_REBOOT = 'De terminal start opnieuw op. Even geduld.'
ROOT_HELPER = '/usr/local/sbin/eventvox-pi-root'
CONFIG = '/etc/eventvox-pi/config'
LOG_LINES = 300
# Alleen op deze pagina's komt window.WebKiosk (de scanterminal, ook op een eigen domein: zie PAGE_MATCH in de config)
DEFAULT_PAGE_MATCH = r'^https://([a-z0-9-]+\.)*eventvox\.nl/scanterminal'
# Instellingen uit EventVOX die een Pi gebruikt; de rest (NFC, trillen, volume, ...) hoort bij de Zebra
SETTINGS = {'update_channel': ('stable', 'beta'), 'auto_update': bool, 'nightly_reload': bool, 'nightly_hour': (0, 23)}
# Nachtelijk bijwerken staat standaard uit (sinds 0.0.13): bijwerken als iemand het in EventVOX vraagt, of aanzetten
DEFAULTS = {'update_channel': 'stable', 'auto_update': False, 'nightly_reload': True, 'nightly_hour': 4}


# ---------- opslag ----------

def path(name):
    return os.path.join(STATE_DIR, name)


def read_json(name, default):
    try:
        with open(path(name), encoding='utf-8') as f:
            value = json.load(f)
        return value if isinstance(value, type(default)) else default
    except (OSError, ValueError):
        return default


def write_json(name, value):
    tmp = path(name) + '.tmp'
    with open(tmp, 'w', encoding='utf-8') as f:
        json.dump(value, f)
    os.replace(tmp, path(name))


def read_text(file, default=''):
    try:
        with open(file, encoding='utf-8', errors='replace') as f:
            return f.read().strip()
    except OSError:
        return default


class Log:
    """Het logboek op de Pi (laatste LOG_LINES regels), voor Diagnose in EventVOX. Nooit wachtwoorden of tokens."""
    def __init__(self):
        self.lines = collections.deque(read_text(path('log.txt')).splitlines()[-LOG_LINES:], maxlen=LOG_LINES)
        self.lock = threading.Lock()

    def add(self, text):
        line = datetime.datetime.now().strftime('%d-%m %H:%M:%S') + ' ' + text
        print(line, flush=True)
        with self.lock:
            self.lines.append(line)
            try:
                with open(path('log.txt'), 'w', encoding='utf-8') as f:
                    f.write('\n'.join(self.lines) + '\n')
            except OSError:
                pass

    def text(self):
        with self.lock:
            return '\n'.join(self.lines)


# ---------- websocket (alleen wat het DevTools-protocol nodig heeft: tekst, ping, close) ----------

class WebSocket:
    def __init__(self, url, timeout=10):
        u = urllib.parse.urlparse(url)
        self.sock = socket.create_connection((u.hostname, u.port or 80), timeout=timeout)
        key = base64.b64encode(os.urandom(16)).decode()
        request = (f'GET {u.path or "/"}{"?" + u.query if u.query else ""} HTTP/1.1\r\nHost: {u.hostname}:{u.port or 80}\r\n'
                   f'Upgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n')
        self.sock.sendall(request.encode())
        head = b''
        while b'\r\n\r\n' not in head:
            chunk = self.sock.recv(1)
            if not chunk:
                raise ConnectionError('websocket: geen antwoord')
            head += chunk
        if b' 101 ' not in head.split(b'\r\n', 1)[0]:
            raise ConnectionError('websocket: ' + head.split(b'\r\n', 1)[0].decode(errors='replace'))
        self.sock.settimeout(None)
        self.send_lock = threading.Lock()

    def _exact(self, n):
        data = b''
        while len(data) < n:
            chunk = self.sock.recv(n - len(data))
            if not chunk:
                raise ConnectionError('websocket gesloten')
            data += chunk
        return data

    def _frame(self, opcode, payload):
        header = bytes([0x80 | opcode])
        n = len(payload)
        if n < 126:
            header += bytes([0x80 | n])
        elif n < 65536:
            header += bytes([0x80 | 126]) + struct.pack('>H', n)
        else:
            header += bytes([0x80 | 127]) + struct.pack('>Q', n)
        mask = os.urandom(4)
        masked = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
        with self.send_lock:
            self.sock.sendall(header + mask + masked)

    def send(self, text):
        self._frame(1, text.encode())

    def recv(self):
        """De volgende tekst; pings worden beantwoord. ConnectionError als de verbinding weg is."""
        message = b''
        while True:
            b1, b2 = self._exact(2)
            opcode, n = b1 & 0x0F, b2 & 0x7F
            if n == 126:
                n = struct.unpack('>H', self._exact(2))[0]
            elif n == 127:
                n = struct.unpack('>Q', self._exact(8))[0]
            mask = self._exact(4) if b2 & 0x80 else None
            payload = self._exact(n)
            if mask:
                payload = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
            if opcode == 8:
                raise ConnectionError('websocket gesloten')
            if opcode == 9:
                self._frame(10, payload)
                continue
            if opcode in (0, 1, 2):
                message += payload
                if b1 & 0x80:
                    return message.decode(errors='replace')

    def close(self):
        try:
            self.sock.close()
        except OSError:
            pass


class Session:
    """Eén DevTools-verbinding (een pagina of de browser): call() wacht op het antwoord, events gaan naar on_event"""
    def __init__(self, url, on_event=None):
        self.ws = WebSocket(url)
        self.next_id = 0
        self.waiting = {}
        self.lock = threading.Lock()
        self.on_event = on_event
        self.alive = True
        threading.Thread(target=self._read, daemon=True).start()

    def _read(self):
        try:
            while True:
                msg = json.loads(self.ws.recv())
                if 'id' in msg:
                    slot = self.waiting.pop(msg['id'], None)
                    if slot:
                        slot[1].append(msg)
                        slot[0].set()
                elif self.on_event:
                    # In een eigen thread: een opdracht roept zelf call() aan, en het antwoord komt via deze lezer
                    threading.Thread(target=self._event, args=(msg.get('method'), msg.get('params') or {}), daemon=True).start()
        except (ConnectionError, OSError, ValueError):
            pass
        self.alive = False
        for slot in list(self.waiting.values()):
            slot[0].set()

    def _event(self, method, params):
        try:
            self.on_event(method, params)
        except Exception as e:  # een fout in een opdracht mag de verbinding niet breken
            print('event:', e, file=sys.stderr, flush=True)

    def call(self, method, params=None, timeout=10):
        with self.lock:
            self.next_id += 1
            i = self.next_id
        slot = (threading.Event(), [])
        self.waiting[i] = slot
        self.ws.send(json.dumps({'id': i, 'method': method, 'params': params or {}}))
        if not slot[0].wait(timeout) or not slot[1]:
            self.waiting.pop(i, None)
            raise ConnectionError(method + ': geen antwoord')
        if 'error' in slot[1][0]:
            raise RuntimeError(method + ': ' + str(slot[1][0]['error'].get('message')))
        return slot[1][0].get('result', {})

    def close(self):
        self.alive = False
        self.ws.close()


# ---------- de Pi zelf ----------

def config():
    """/etc/eventvox-pi/config (KEY=waarde, door install.sh geschreven)"""
    out = {}
    for line in read_text(CONFIG).splitlines():
        m = re.match(r'^\s*([A-Z_]+)=(.*)$', line)
        if m:
            out[m.group(1)] = m.group(2).strip().strip('"\'')
    return out


def serial():
    m = re.search(r'^Serial\s*:\s*0*([0-9a-fA-F]+)', read_text('/proc/cpuinfo'), re.M)
    return m.group(1) if m else socket.gethostname()


def run(cmd, timeout=5):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout).stdout
    except (OSError, subprocess.SubprocessError):
        return ''


def wifi():
    """Zoals de kiosk-app: { connected, level 0-4, rssi, ssid?, link_speed, frequency }; None zonder wifi op de Pi"""
    link = run(['iw', 'dev', 'wlan0', 'link'])
    if 'Connected to' in link:
        rssi = re.search(r'signal:\s*(-?\d+)', link)
        rssi = int(rssi.group(1)) if rssi else -100
        out = {'connected': True, 'rssi': rssi, 'level': max(0, min(4, (rssi + 100) * 4 // 45))}
        for key, pattern, cast in (('ssid', r'SSID:\s*(.+)', str), ('frequency', r'freq:\s*(\d+)', int),
                                   ('link_speed', r'tx bitrate:\s*([\d.]+)', lambda v: int(float(v)))):
            m = re.search(pattern, link)
            if m:
                out[key] = cast(m.group(1).strip())
        return out
    return {'connected': False} if os.path.exists('/sys/class/net/wlan0') else None


def ethernet():
    """De netwerkkabel: { connected, speed_mbps? }; None zonder netwerkpoort"""
    names = sorted(n for n in os.listdir('/sys/class/net') if n.startswith(('eth', 'en'))) if os.path.isdir('/sys/class/net') else []
    if not names:
        return None
    base = '/sys/class/net/' + names[0]
    connected = read_text(base + '/carrier') == '1' and read_text(base + '/operstate') == 'up'
    out = {'connected': connected}
    speed = read_text(base + '/speed')
    if connected and speed.isdigit() and int(speed) > 0:
        out['speed_mbps'] = int(speed)
    return out


def uplink():
    """Via welke verbinding de Pi nu internet heeft (de standaardroute): 'ethernet', 'wifi' of None"""
    m = re.search(r'\bdev (\S+)', run(['ip', 'route', 'get', '1.1.1.1']))
    if not m:
        return None
    dev = m.group(1)
    return 'ethernet' if dev.startswith(('eth', 'en')) else 'wifi' if dev.startswith('wl') else None


def pi_health():
    """{ model, temperature_c, undervoltage, undervoltage_seen, throttled, disk_free_mb, disk_total_mb }, alleen wat bekend is"""
    out = {}
    model = read_text('/proc/device-tree/model').replace('\x00', '')
    if model:
        out['model'] = model[:60]
    t = read_text('/sys/class/thermal/thermal_zone0/temp')
    if t.isdigit():
        out['temperature_c'] = round(int(t) / 1000, 1)
    m = re.search(r'throttled=(0x[0-9a-fA-F]+)', run(['vcgencmd', 'get_throttled']))
    if m:
        bits = int(m.group(1), 16)
        out['undervoltage'] = bool(bits & 0x1)
        out['throttled'] = bool(bits & 0x4)
        out['undervoltage_seen'] = bool(bits & 0x10000)
    try:
        st = os.statvfs('/')
        out['disk_free_mb'] = st.f_bavail * st.f_frsize // 1048576
        out['disk_total_mb'] = st.f_blocks * st.f_frsize // 1048576
    except OSError:
        pass
    return out


def iso(ts):
    return datetime.datetime.fromtimestamp(ts).astimezone().isoformat(timespec='seconds')


# ---------- de agent ----------

class Agent:
    def __init__(self):
        os.makedirs(STATE_DIR, exist_ok=True)
        self.log = Log()
        self.cfg = config()
        self.page_match = re.compile(os.environ.get('EVX_PI_PAGE_MATCH') or self.cfg.get('PAGE_MATCH') or DEFAULT_PAGE_MATCH)
        self.version = read_text(os.path.join(HOME, 'VERSION'), '0.0.0-dev')
        self.state = read_json('state.json', {})   # last_command_id, settings_version, settings, nightly_day, ...
        self.bridge = read_text(os.path.join(HOME, 'bridge.js'))
        self.locate_js = read_text(os.path.join(HOME, 'locate.js'))
        self.refresh_js = read_text(os.path.join(HOME, 'refresh.js'))
        self.maintenance_js = read_text(os.path.join(HOME, 'maintenance.js'))
        self.maintenance = None   # de tekst die nu op het scherm staat (None: geen onderhoud)
        self.page = None
        self.page_id = None
        self.log_id = 0
        self.diag = None          # het logboek dat met de volgende heartbeats meegaat (na Diagnose)
        self.clock_skew = None
        self.clock_checked = 0
        self.last_push = None
        self.lock = threading.Lock()
        self.rpic = None          # laatste staat van Raspberry Pi Connect { installed, signed_in }
        self.rpic_at = 0
        self.rpic_pending = None  # { verify_url, until } zolang een koppellink op goedkeuring wacht
        self.rpic_busy = False

    def save(self):
        write_json('state.json', self.state)

    def setting(self, key):
        return self.state.get('settings', {}).get(key, DEFAULTS[key])

    # --- de staat voor de pagina ---

    def browser_exits(self):
        """Onverwachte stops van Chromium (kiosk.sh schrijft ze; een gevraagde herstart telt niet)"""
        times = [int(x) for x in read_text(path('browser-exits')).split() if x.isdigit()]
        return len(times), (iso(times[-1]) if times else None)

    def status(self):
        crashes, last = self.browser_exits()
        update = read_json('update-result.json', {})
        s = {
            'app': 'pi', 'version': self.version, 'channel': self.setting('update_channel'),
            'uptime_s': int(float(read_text('/proc/uptime', '0').split()[0] or 0)),
            'crashes': crashes, 'settings_version': self.state.get('settings_version', 0),
            'command_done': self.state.get('last_command_id', 0), 'pi': pi_health(),
        }
        if last:
            s['last_crash_at'] = last
        w = wifi()
        if w is not None:
            s['wifi'] = w
        e = ethernet()
        if e is not None:
            s['ethernet'] = e
        up = uplink()
        if up:
            s['uplink'] = up
        if self.clock_skew is not None:
            s['clock_skew_s'] = self.clock_skew
        # Ook leeg: zo weet EventVOX dat deze versie wifi-netwerken kan ontvangen (kiosk_wifi)
        wifi_done = read_json('wifi-result.json', {})
        s['wifi_version'] = wifi_done.get('version', '') if isinstance(wifi_done.get('version'), str) else ''
        if wifi_done.get('result'):
            s['wifi_result'] = str(wifi_done['result'])[:200]
        ssh_done = read_json('ssh-result.json', {})
        s['ssh_version'] = ssh_done.get('version', '') if isinstance(ssh_done.get('version'), str) else ''
        if ssh_done.get('result'):
            s['ssh_result'] = str(ssh_done['result'])[:200]
        c = self.rpi_connect_state()
        if c is not None:
            c = dict(c)
            if self.rpic_pending:
                c.update(self.rpic_pending)
            s['connect'] = c
        if update.get('checked_at'):
            s['update'] = {'checked_at': update['checked_at'], 'result': str(update.get('result', ''))[:160]}
        return s

    def page_state(self):
        out = {'status': self.status(), 'serial': serial(),
               'device': {'serial': serial(), 'model': pi_health().get('model', 'Raspberry Pi'), 'appVersion': self.version}}
        if self.diag is not None:
            out['log'] = self.diag
            out['log_id'] = self.log_id
        return out

    def push(self, force=False):
        """De staat naar de pagina (alleen als die veranderd is, of force)"""
        page = self.page
        if not page or not page.alive:
            return
        state = json.dumps(self.page_state())
        if not force and state == self.last_push:
            return
        try:
            page.call('Runtime.evaluate', {'expression': f'window.__evxPiState && window.__evxPiState({state})'})
            self.last_push = state
        except (ConnectionError, RuntimeError):
            pass

    # --- wat de pagina vraagt (window.__evxPi) ---

    def on_event(self, method, params):
        if method == 'Runtime.bindingCalled' and params.get('name') == '__evxPi':
            msg = json.loads(params.get('payload') or '{}')
            kind = msg.get('type')
            if kind == 'hello':
                self.push(True)  # een nieuwe pagina: meteen de actuele staat
            elif kind == 'command':
                self.command(msg.get('value', ''))
            elif kind == 'settings':
                self.settings(msg.get('value', ''))
            elif kind == 'wifi':
                self.wifi(msg.get('value', ''))
            elif kind == 'ssh':
                self.ssh(msg.get('value', ''))
            elif kind == 'diagnostics':
                self.log.add('Diagnose gevraagd door EventVOX')
                self.diag = self.log.text() + '\n' + self.diag_extra()
                self.log_id += 1
                self.push(True)
            elif kind == 'logSent':
                if msg.get('id') == self.log_id:
                    self.diag = None
                    self.log.add('Diagnose verstuurd')
        elif method == 'Page.loadEventFired':
            self.push(True)
            if self.maintenance:
                self.show_maintenance(self.maintenance, force=True)  # na herladen opnieuw tonen

    def diag_extra(self):
        h = pi_health()
        lines = ['--- Pi: ' + json.dumps(h), '--- schijf: ' + run(['df', '-h', '/']).strip().replace('\n', ' | ')]
        exits, last = self.browser_exits()
        lines.append(f'--- Chromium onverwacht gestopt: {exits}x' + (f', laatst {last}' if last else ''))
        card = run(['lsblk', '-dno', 'SIZE', '/dev/mmcblk0']).strip()
        if card:
            lines.append('--- SD-kaart: ' + card)
        clean = read_json('cleanup-result.json', {})
        if clean.get('result'):
            when = time.strftime('%Y-%m-%d %H:%M', time.localtime(clean.get('at', 0)))
            lines.append(f"--- Onderhoud {when}: {str(clean['result'])[:200]}")
        return '\n'.join(lines)

    def command(self, raw):
        try:
            o = json.loads(raw)
            cid, name = int(o['id']), str(o['command'])
        except (ValueError, KeyError, TypeError):
            return
        with self.lock:
            if cid <= self.state.get('last_command_id', 0):
                self.push(True)  # al uitgevoerd: de pagina meldt het als gedaan
                return
            self.state['last_command_id'] = cid  # eerst opslaan: herstarten en bijwerken stoppen de agent
            self.save()
        self.log.add('Opdracht uit EventVOX: ' + name)
        self.push(True)  # command_done meteen terug, ook als de opdracht de pagina of de Pi herstart
        time.sleep(1)
        if name == 'reload':
            self.reload()
        elif name == 'restart':
            self.restart_browser('opdracht uit EventVOX')
        elif name == 'reboot':
            self.show_maintenance(MAINTENANCE_REBOOT)
            self.root('reboot')
        elif name == 'update':
            self.root('update')
        elif name == 'update_app':
            self.root('update-app')
        elif name == 'locate':
            self.locate()
        elif name == 'refresh_screen':
            self.refresh_screen()
        elif name == 'connect_signin':
            threading.Thread(target=self.rpi_connect_signin, daemon=True).start()
        elif name == 'connect_signout':
            threading.Thread(target=self.rpi_connect_signout, daemon=True).start()
        else:
            self.log.add('Onbekende opdracht: ' + name)

    def settings(self, raw):
        try:
            o = json.loads(raw)
            version, values = int(o['version']), o.get('values') or {}
        except (ValueError, KeyError, TypeError):
            return
        if version == self.state.get('settings_version'):
            return
        applied = {}
        for key, rule in SETTINGS.items():
            if key not in values:
                continue
            v = values[key]
            if rule is bool and isinstance(v, bool):
                applied[key] = v
            elif isinstance(rule, tuple) and isinstance(rule[0], str) and v in rule:
                applied[key] = v
            elif isinstance(rule, tuple) and isinstance(rule[0], int) and isinstance(v, int) and rule[0] <= v <= rule[1]:
                applied[key] = v
        self.state['settings'] = applied
        self.state['settings_version'] = version
        self.save()
        self.log.add('Instellingen uit EventVOX: ' + (', '.join(sorted(applied)) or 'weer die van de Pi'))
        self.push(True)

    def wifi(self, raw):
        """Wifi-netwerken uit EventVOX: alleen een andere versie; via sudo naar wifi.py (stdin, nooit in een bestand)"""
        try:
            o = json.loads(raw)
            version = o['version']
            if not isinstance(version, str) or not re.fullmatch(r'[0-9a-f]{16}', version) or not isinstance(o.get('networks', []), list):
                return
        except (ValueError, KeyError, TypeError):
            return
        with self.lock:
            if version == read_json('wifi-result.json', {}).get('version') or getattr(self, 'wifi_busy', False):
                return
            self.wifi_busy = True
        try:
            self.root('wifi', json.dumps({'version': version, 'networks': o.get('networks') or []}))
            done = read_json('wifi-result.json', {})
            self.log.add('Wifi uit EventVOX: ' + str(done.get('result', 'geen uitkomst'))[:200])
        finally:
            self.wifi_busy = False
        self.push(True)

    def ssh(self, raw):
        """SSH-sleutels van de beheerders uit EventVOX: alleen een andere versie; via sudo naar ssh.py (stdin)"""
        try:
            o = json.loads(raw)
            version = o['version']
            if not isinstance(version, str) or not re.fullmatch(r'[0-9a-f]{16}', version) or not isinstance(o.get('keys', []), list):
                return
        except (ValueError, KeyError, TypeError):
            return
        with self.lock:
            if version == read_json('ssh-result.json', {}).get('version') or getattr(self, 'ssh_busy', False):
                return
            self.ssh_busy = True
        try:
            self.root('ssh', json.dumps({'version': version, 'keys': o.get('keys') or []}))
            self.log.add('SSH-sleutels uit EventVOX: ' + str(read_json('ssh-result.json', {}).get('result', 'geen uitkomst'))[:200])
        finally:
            self.ssh_busy = False
        self.push(True)

    # --- acties ---

    def reload(self):
        if self.page and self.page.alive:
            try:
                self.page.call('Page.reload', {'ignoreCache': True})
            except (ConnectionError, RuntimeError):
                pass

    def restart_browser(self, why):
        """Chromium netjes sluiten; kiosk.sh start hem meteen opnieuw (telt niet als crash)"""
        self.log.add('Browser herstarten: ' + why)
        try:
            with open(path('restart-requested'), 'w') as f:
                f.write(str(int(time.time())))
            version = json.loads(urllib.request.urlopen(CDP + '/json/version', timeout=5).read())
            browser = Session(version['webSocketDebuggerUrl'])
            try:
                browser.call('Browser.close', timeout=3)
            except ConnectionError:
                pass  # de browser is al weg voor hij antwoordt
            browser.close()
        except (OSError, ValueError, KeyError, RuntimeError) as e:
            self.log.add('Browser herstarten mislukt: ' + str(e))

    def root(self, action, stdin=None):
        """Pi herstarten, bijwerken (alles of alleen EventVOX-Pi), wifi of SSH-sleutels zetten (als root, via sudo). stdin: invoer"""
        if action not in ('wifi', 'ssh'):
            what = {'reboot': 'Pi herstarten', 'update': 'Alles bijwerken gestart', 'update-app': 'EventVOX-Pi bijwerken gestart'}.get(action, action)
            self.log.add(what + (' (proef, niet echt)' if DRYRUN else ''))
        if DRYRUN:
            with open(path('dryrun-actions'), 'a') as f:
                f.write(action + '\n')
            script = {'wifi': os.environ.get('EVX_PI_WIFI'), 'ssh': os.environ.get('EVX_PI_SSH')}.get(action)
            if script:
                # Tests: wifi.py / ssh.py zonder sudo (EVX_PI_WIFI / EVX_PI_SSH = pad naar het script)
                subprocess.run([sys.executable, script], input=stdin, capture_output=True, text=True,
                               env={**os.environ, 'EVX_PI_STATE': STATE_DIR})
            return
        r = subprocess.run(['sudo', '-n', ROOT_HELPER, action], input=stdin, capture_output=True, text=True, timeout=180)
        if r.returncode != 0:
            self.log.add(f'{action} mislukt: ' + (r.stderr or r.stdout).strip()[:200])

    # --- Raspberry Pi Connect ---

    def rpi_connect_state(self, refresh=False):
        """{ installed, signed_in } (hoogstens elke minuut gevraagd), None als rpi-connect er niet is"""
        if not refresh and self.rpic_at and time.time() - self.rpic_at < 60:
            return self.rpic
        try:
            out = subprocess.run([RPI_CONNECT, 'status'], capture_output=True, text=True, timeout=10)
            text = out.stdout + out.stderr
            m = re.search(r'Signed in:\s*(yes|no)', text, re.I)
            self.rpic = {'installed': True, 'signed_in': bool(m and m.group(1).lower() == 'yes')}
        except FileNotFoundError:
            self.rpic = None
        except (OSError, subprocess.SubprocessError):
            pass  # houd de vorige staat
        self.rpic_at = time.time()
        return self.rpic

    def rpi_connect_signin(self):
        """Koppelen met Raspberry Pi Connect: rpi-connect signin geeft een koppellink; die gaat met de status naar
        EventVOX, waar een beheerder hem opent en goedkeurt. De link komt niet in het logboek."""
        with self.lock:
            if self.rpic_busy:
                return
            self.rpic_busy = True
        try:
            st = self.rpi_connect_state(refresh=True)
            if st is None:
                self.log.add('Raspberry Pi Connect: niet geïnstalleerd')
                return
            if st.get('signed_in'):
                self.log.add('Raspberry Pi Connect: al gekoppeld')
                self.push(True)
                return
            run([RPI_CONNECT, 'on'], timeout=20)
            try:
                proc = subprocess.Popen([RPI_CONNECT, 'signin'], stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                        stderr=subprocess.STDOUT, text=True)
            except OSError:
                self.log.add('Raspberry Pi Connect: koppelen lukte niet')
                return
            timer = threading.Timer(CONNECT_WAIT_S, proc.kill)
            timer.start()
            for line in proc.stdout:
                m = CONNECT_VERIFY.search(line)
                if m and not self.rpic_pending:
                    self.rpic_pending = {'verify_url': m.group(0), 'verify_until': iso(time.time() + CONNECT_WAIT_S)}
                    self.log.add('Raspberry Pi Connect: koppellink klaar, wacht op goedkeuring')
                    self.push(True)
            proc.wait()
            timer.cancel()
            self.rpic_pending = None
            ok = self.rpi_connect_state(refresh=True) or {}
            self.log.add('Raspberry Pi Connect: ' + ('gekoppeld' if ok.get('signed_in') else 'niet gekoppeld (link niet goedgekeurd of verlopen)'))
        finally:
            self.rpic_pending = None
            self.rpic_busy = False
            self.push(True)

    def rpi_connect_signout(self):
        if self.rpi_connect_state(refresh=True) is None:
            return
        run([RPI_CONNECT, 'signout'], timeout=30)
        ok = self.rpi_connect_state(refresh=True) or {}
        self.log.add('Raspberry Pi Connect: ' + ('nog gekoppeld' if ok.get('signed_in') else 'ontkoppeld'))
        self.push(True)

    def locate(self):
        if self.page and self.page.alive and self.locate_js:
            try:
                self.page.call('Runtime.evaluate', {'expression': self.locate_js, 'userGesture': True})
            except (ConnectionError, RuntimeError):
                pass

    def refresh_screen(self):
        """Scherm opfrissen (refresh.js): hoogstens 3 uur wisselende kleuren tegen beeldretentie; een tik of toets stopt het"""
        if self.page and self.page.alive and self.refresh_js:
            try:
                self.page.call('Runtime.evaluate', {'expression': self.refresh_js})
                self.log.add('Scherm opfrissen gestart (hoogstens 3 uur; een tik of toets stopt het)')
            except (ConnectionError, RuntimeError):
                pass

    # --- verbinding met Chromium ---

    def connect(self):
        """De pagina zoeken en window.WebKiosk erin zetten (ook voor elke volgende pagina)"""
        targets = json.loads(urllib.request.urlopen(CDP + '/json/list', timeout=5).read())
        pages = [t for t in targets if t.get('type') == 'page' and t.get('webSocketDebuggerUrl')]
        if not pages:
            return
        # De scanterminal als die open is, anders de eerste pagina (in de kiosk is er maar één)
        target = next((t for t in pages if self.page_match.search(t.get('url', ''))), pages[0])
        if self.page and self.page.alive and self.page_id == target['id']:
            return
        if self.page:
            self.page.close()
        self.page = Session(target['webSocketDebuggerUrl'], self.on_event)
        self.page_id = target['id']
        self.last_push = None
        source = self.bridge.replace('__EVX_PI_STATE__', json.dumps(self.page_state()))
        # Alleen op de scanterminal (een andere pagina, zoals een foutpagina, krijgt niets)
        guarded = f'if (new RegExp({json.dumps(self.page_match.pattern)}).test(location.href)) {{ {source} }}'
        self.page.call('Runtime.enable')
        self.page.call('Page.enable')
        self.page.call('Runtime.addBinding', {'name': '__evxPi'})
        self.page.call('Page.addScriptToEvaluateOnNewDocument', {'source': guarded})
        self.log.add('Verbonden met Chromium: ' + re.sub(r'\?.*', '', target.get('url', '')))
        if self.page_match.search(target.get('url', '')):
            # De scanterminal was al geladen (en heeft misschien al een heartbeat zonder deze staat gestuurd):
            # één keer opnieuw laden, zodat window.WebKiosk er is vóór de scripts van de pagina
            self.page.call('Page.reload')
        else:
            self.page.call('Runtime.evaluate', {'expression': guarded})

    def check_clock(self):
        """Klok van de Pi min die van de website (Date-header), elk half uur; een Pi zonder netwerk-tijd loopt weg"""
        if time.time() - self.clock_checked < 1800:
            return
        self.clock_checked = time.time()
        url = self.cfg.get('URL', 'https://eventvox.nl/scanterminal/').replace('{serial}', '')
        try:
            req = urllib.request.Request(re.sub(r'\?.*', '', url), method='HEAD')
            with urllib.request.urlopen(req, timeout=10) as r:
                date = r.headers.get('Date')
            if date:
                server = datetime.datetime.strptime(date, '%a, %d %b %Y %H:%M:%S GMT').replace(tzinfo=datetime.timezone.utc)
                self.clock_skew = int(time.time() - server.timestamp())
        except (OSError, ValueError):
            pass

    def nightly(self):
        """Elke nacht om nightly_hour: bijwerken (auto_update) of anders de browser herstarten (geheugen)"""
        if not self.setting('nightly_reload') and not self.setting('auto_update'):
            return
        now = datetime.datetime.now()
        today = now.strftime('%Y-%m-%d')
        if now.hour != self.setting('nightly_hour') or self.state.get('nightly_day') == today:
            return
        if self.idle_seconds() < 300:
            return  # er wordt gescand: later in dit uur opnieuw proberen
        self.state['nightly_day'] = today
        self.save()
        if self.setting('auto_update'):
            self.root('update')  # herstart de Pi alleen als er iets nieuws is
        if self.setting('nightly_reload'):
            self.restart_browser('nachtelijk herladen')

    def idle_seconds(self):
        """Seconden sinds de laatste scan of tik op de scanterminal (onbekend: als rustig)"""
        if not self.page or not self.page.alive:
            return 10 ** 6
        try:
            r = self.page.call('Runtime.evaluate', {'expression': 'window.__evxPiIdleSeconds ? window.__evxPiIdleSeconds() : 1000000',
                                                     'returnByValue': True})
            return int(r.get('result', {}).get('value', 10 ** 6))
        except (ConnectionError, RuntimeError, ValueError, TypeError):
            return 10 ** 6

    # --- onderhoud op het scherm ---

    def show_maintenance(self, text, force=False):
        """Onderhoud op het scherm (text) of weer weg (None)"""
        if text == self.maintenance and not force:
            return
        self.maintenance = text
        if self.page and self.page.alive and self.maintenance_js:
            try:
                self.page.call('Runtime.evaluate', {'expression': self.maintenance_js + f'window.__evxMaintenance({json.dumps(text)})'})
            except (ConnectionError, RuntimeError):
                pass

    def update_running(self):
        """Of eventvox-pi-update.service bezig is. Niet de afsluitcode van is-active: die is alleen 0 bij "active", en een
        eenmalige dienst is tijdens het bijwerken "activating" (daardoor stond er tot v0.0.12 nooit Onderhoud)."""
        try:
            out = subprocess.run([SYSTEMCTL, 'is-active', 'eventvox-pi-update.service', 'eventvox-pi-update-app.service'],
                                 capture_output=True, text=True, timeout=5)
            return any(line.strip() in UPDATE_BUSY for line in out.stdout.splitlines())
        except (OSError, subprocess.SubprocessError):
            return False

    def check_maintenance(self):
        running = self.update_running()
        if running and self.maintenance != MAINTENANCE_UPDATE:
            self.log.add('Onderhoud: bijwerken loopt')
            self.show_maintenance(MAINTENANCE_UPDATE)
        elif not running and self.maintenance == MAINTENANCE_UPDATE:
            self.log.add('Onderhoud klaar')
            self.show_maintenance(None)

    # --- NFC-lezers zonder toetsenbord-modus (PC/SC, bijvoorbeeld de ACS ACR122U) ---

    def type_text(self, text):
        """Typen in de scanterminal, met Enter erachter, zoals een scanner-toetsenbord"""
        page = self.page
        if not page or not page.alive:
            return
        try:
            # Elk teken als echte toetsaanslag: de scanterminal leest keydown, zoals van een scanner-toetsenbord
            for ch in text:
                page.call('Input.dispatchKeyEvent', {'type': 'keyDown', 'key': ch, 'text': ch, 'unmodifiedText': ch})
                page.call('Input.dispatchKeyEvent', {'type': 'keyUp', 'key': ch})
            for kind in ('keyDown', 'keyUp'):
                page.call('Input.dispatchKeyEvent', {'type': kind, 'key': 'Enter', 'code': 'Enter', 'windowsVirtualKeyCode': 13,
                                                     'nativeVirtualKeyCode': 13, **({'text': '\r'} if kind == 'keyDown' else {})})
        except (ConnectionError, RuntimeError):
            pass

    def nfc_uids(self):
        """Elke ronde: het nummer van de kaart op een lezer (of None). Echt: PC/SC (pcscd + pyscard); tests: een bestand."""
        if NFC_FAKE:
            offset = 0
            while True:
                try:
                    with open(NFC_FAKE, encoding='utf-8') as f:
                        f.seek(offset)
                        line = f.readline()
                        if line.endswith('\n'):
                            offset = f.tell()
                            yield line.strip() or None
                            continue
                except OSError:
                    pass
                yield None
                time.sleep(0.25)
        try:
            from smartcard.System import readers
        except ImportError:
            self.log.add('NFC: pyscard ontbreekt (alleen lezers die zelf typen werken)')
            return
        warned = False
        while True:
            uid = None
            try:
                for r in readers():
                    try:
                        c = r.createConnection()
                        c.connect()
                        data, sw1, sw2 = c.transmit([0xFF, 0xCA, 0x00, 0x00, 0x00])  # het nummer (UID) van de kaart
                        c.disconnect()
                        if (sw1, sw2) == (0x90, 0x00) and data:
                            uid = ''.join('%02X' % b for b in data)
                            break
                    except Exception:  # geen kaart op deze lezer, of de lezer is net weg
                        continue
            except Exception as e:  # pcscd niet bereikbaar
                if not warned:
                    self.log.add('NFC: PC/SC niet bereikbaar (' + type(e).__name__ + ')')
                    warned = True
            yield uid
            time.sleep(0.25)

    def nfc_loop(self):
        """Een kaart die op de lezer komt één keer typen (blijft hij liggen: niet opnieuw); nooit het nummer in het logboek"""
        present, gone_at = None, 0.0
        for uid in self.nfc_uids():
            now = time.time()
            if uid is None:
                if present and now - gone_at > 1.0:
                    present = None
                continue
            gone_at = now
            if uid != present:
                present = uid
                self.log.add('NFC-kaart gelezen')
                self.type_text(uid)

    def run(self):
        self.log.add('EventVOX-Pi ' + self.version + ' gestart')
        threading.Thread(target=self.nfc_loop, daemon=True).start()
        while True:
            try:
                self.connect()
                self.push()
                self.check_maintenance()
                self.check_clock()
                self.nightly()
            except (OSError, ValueError, ConnectionError, RuntimeError):
                pass  # Chromium (nog) niet bereikbaar: volgende ronde opnieuw
            time.sleep(TICK)


if __name__ == '__main__':
    Agent().run()
