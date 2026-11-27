#!/usr/bin/env python3
"""
Wifi-netwerken uit EventVOX op de Pi zetten (als root, via eventvox-pi-root wifi). Leest van stdin
{ version, networks: [{ ssid, security WPA|WEP|OPEN, password, hidden, priority }] } en maakt per netwerk een
NetworkManager-verbinding "evx-<code>". Verbindingen met die naam die niet meer in de lijst staan, worden verwijderd;
andere verbindingen (uit Imager, met de hand) nooit. De wachtwoorden komen nooit in een bestand of logboek van ons
(NetworkManager bewaart ze zelf, alleen leesbaar voor root). De uitkomst gaat naar /var/lib/eventvox-pi/wifi-result.json.
Omgeving (tests): EVX_PI_STATE, NMCLI (het nmcli-programma).
"""
import hashlib
import json
import os
import re
import subprocess
import sys
import datetime

STATE = os.environ.get('EVX_PI_STATE', '/var/lib/eventvox-pi')
NMCLI = os.environ.get('NMCLI', 'nmcli')
PREFIX = 'evx-'


def wlan():
    """De wifi-interface: wlan0 op een Pi, op een pc vaak een andere naam (wlp2s0). Tests: EVX_PI_SYSFS"""
    base = os.path.join(os.environ.get('EVX_PI_SYSFS', '/sys'), 'class/net')
    if os.path.exists(os.path.join(base, 'wlan0')) or not os.path.isdir(base):
        return 'wlan0'
    names = sorted(n for n in os.listdir(base) if os.path.isdir(os.path.join(base, n, 'wireless')))
    return names[0] if names else 'wlan0'


def nm(*args):
    return subprocess.run([NMCLI, *args], capture_output=True, text=True, timeout=30)


def valid(n):
    """Strenge controle: de lijst komt van de kiosk-gebruiker; alles gaat als losse argumenten naar nmcli (geen shell)"""
    if not isinstance(n, dict):
        return None
    ssid, security, password = n.get('ssid'), n.get('security'), n.get('password') or ''
    if not isinstance(ssid, str) or not ssid or len(ssid.encode()) > 32 or re.search(r'[\x00-\x1f\x7f]', ssid):
        return None
    if security not in ('WPA', 'WEP', 'OPEN') or not isinstance(password, str) or re.search(r'[\x00-\x1f\x7f]', password):
        return None
    if security == 'WPA' and not 8 <= len(password) <= 63:
        return None
    if security == 'WEP' and not (len(password) in (5, 13) or re.fullmatch(r'[0-9a-fA-F]{10}|[0-9a-fA-F]{26}', password)):
        return None
    priority = n.get('priority') if isinstance(n.get('priority'), int) and 0 <= n.get('priority') <= 100 else 0
    return {'ssid': ssid, 'security': security, 'password': password, 'hidden': n.get('hidden') is True, 'priority': priority}


def name(ssid):
    return PREFIX + hashlib.sha1(ssid.encode()).hexdigest()[:10]


def main():
    try:
        data = json.loads(sys.stdin.read(200000))
        version = data['version']
        if not isinstance(version, str) or not re.fullmatch(r'[0-9a-f]{16}', version):
            raise ValueError('versie')
        networks = [valid(n) for n in (data.get('networks') or [])[:20]]
    except (ValueError, KeyError, TypeError):
        print('ongeldige invoer', file=sys.stderr)
        return 2
    skipped = sum(1 for n in networks if n is None)
    networks = [n for n in networks if n]
    try:
        existing = [line.split(':', 1)[0] for line in nm('-t', '-f', 'NAME', 'connection', 'show').stdout.splitlines()]
    except (OSError, subprocess.SubprocessError):
        return result(version, 'Niet gezet: NetworkManager (nmcli) ontbreekt', [])
    wanted = {name(n['ssid']) for n in networks}
    ok, failed, removed, names = 0, 0, 0, []
    for n in networks:
        con = name(n['ssid'])
        if con in existing:
            nm('connection', 'delete', con)
        args = ['connection', 'add', 'type', 'wifi', 'con-name', con, 'ifname', wlan(), 'ssid', n['ssid'],
                'connection.autoconnect', 'yes', 'connection.autoconnect-priority', str(n['priority'])]
        if n['hidden']:
            args += ['wifi.hidden', 'yes']
        if n['security'] == 'WPA':
            args += ['wifi-sec.key-mgmt', 'wpa-psk', 'wifi-sec.psk', n['password']]
        elif n['security'] == 'WEP':
            args += ['wifi-sec.key-mgmt', 'none', 'wifi-sec.wep-key-type', '1', 'wifi-sec.wep-key0', n['password']]
        if nm(*args).returncode == 0:
            ok += 1
            names.append(n['ssid'])
        else:
            failed += 1
    for con in existing:
        if con.startswith(PREFIX) and con not in wanted and nm('connection', 'delete', con).returncode == 0:
            removed += 1
    text = f'{ok} ingesteld' + (f', {failed} mislukt' if failed else '') + (f', {removed} verwijderd' if removed else '') \
        + (f', {skipped} ongeldig' if skipped else '') if networks or removed or skipped else 'Geen netwerken uit EventVOX'
    return result(version, text + (f' ({", ".join(sorted(names))})' if names else ''), names)


def result(version, text, names):
    out = {'version': version, 'result': text[:200], 'ssids': names,
           'at': datetime.datetime.now().astimezone().isoformat(timespec='seconds')}
    path = os.path.join(STATE, 'wifi-result.json')
    with open(path + '.tmp', 'w', encoding='utf-8') as f:
        json.dump(out, f)
    os.replace(path + '.tmp', path)
    try:
        st = os.stat(STATE)
        os.chown(path, st.st_uid, st.st_gid)
    except OSError:
        pass
    print(text)
    return 0


if __name__ == '__main__':
    sys.exit(main())
