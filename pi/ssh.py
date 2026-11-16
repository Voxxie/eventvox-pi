#!/usr/bin/env python3
"""
SSH-sleutels van de beheerders uit EventVOX op de Pi zetten (als root, via eventvox-pi-root ssh). Leest van stdin
{ version, keys: ["type base64 eventvox:naam", ...] } en schrijft ze in een eigen blok van ~/.ssh/authorized_keys van de
kiosk-gebruiker. Sleutels buiten dat blok (bijvoorbeeld uit Raspberry Pi Imager) blijven altijd staan. Alleen publieke
sleutels zonder opties, streng gecontroleerd. De uitkomst gaat naar /var/lib/eventvox-pi/ssh-result.json.
Omgeving (tests): EVX_PI_STATE, EVX_PI_SSH_HOME (de home-map van de kiosk-gebruiker).
"""
import base64
import datetime
import json
import os
import pwd
import re
import struct
import sys

STATE = os.environ.get('EVX_PI_STATE', '/var/lib/eventvox-pi')
BEGIN = '# EventVOX-Pi: begin (beheerd vanuit EventVOX, niet met de hand wijzigen)'
END = '# EventVOX-Pi: eind'
TYPES = ('ssh-ed25519', 'ssh-rsa', 'ecdsa-sha2-nistp256', 'ecdsa-sha2-nistp384', 'ecdsa-sha2-nistp521',
         'sk-ssh-ed25519@openssh.com', 'sk-ecdsa-sha2-nistp256@openssh.com')


def valid(line):
    """'type base64 comment' met een bekend type, geldige base64 en hetzelfde type in de sleutel; anders None"""
    if not isinstance(line, str) or len(line) > 16384 or re.search(r'[\x00-\x1f\x7f]', line):
        return None
    parts = line.split(' ')
    if len(parts) not in (2, 3) or parts[0] not in TYPES:
        return None
    try:
        blob = base64.b64decode(parts[1], validate=True)
        (n,) = struct.unpack('>I', blob[:4])
        if blob[4:4 + n].decode() != parts[0]:
            return None
    except (ValueError, struct.error, UnicodeDecodeError):
        return None
    comment = parts[2] if len(parts) == 3 and re.fullmatch(r'[\w.@:-]{1,120}', parts[2]) else 'eventvox'
    return f'{parts[0]} {parts[1]} {comment}'


def kiosk_home():
    if os.environ.get('EVX_PI_SSH_HOME'):
        return os.environ['EVX_PI_SSH_HOME']
    user = ''
    try:
        for line in open('/etc/eventvox-pi/config', encoding='utf-8'):
            if line.startswith('KIOSK_USER='):
                user = line.split('=', 1)[1].strip().strip('"\'')
    except OSError:
        pass
    return pwd.getpwnam(user).pw_dir if user else pwd.getpwuid(1000).pw_dir


def main():
    try:
        data = json.loads(sys.stdin.read(400000))
        version = data['version']
        if not isinstance(version, str) or not re.fullmatch(r'[0-9a-f]{16}', version) or not isinstance(data.get('keys', []), list):
            raise ValueError
    except (ValueError, KeyError, TypeError):
        print('ongeldige invoer', file=sys.stderr)
        return 2
    keys = [valid(k) for k in data.get('keys', [])[:50]]
    skipped = sum(1 for k in keys if k is None)
    keys = [k for k in keys if k]
    home = kiosk_home()
    st = os.stat(home)
    ssh_dir = os.path.join(home, '.ssh')
    path = os.path.join(ssh_dir, 'authorized_keys')
    os.makedirs(ssh_dir, mode=0o700, exist_ok=True)
    os.chown(ssh_dir, st.st_uid, st.st_gid)
    os.chmod(ssh_dir, 0o700)
    try:
        lines = open(path, encoding='utf-8').read().splitlines()
    except OSError:
        lines = []
    # Het oude blok eruit, de rest blijft
    kept, inside = [], False
    for line in lines:
        if line == BEGIN:
            inside = True
        elif line == END:
            inside = False
        elif not inside:
            kept.append(line)
    out = kept + ([BEGIN, *keys, END] if keys else [])
    tmp = path + '.evx'
    with open(tmp, 'w', encoding='utf-8') as f:
        f.write('\n'.join(out) + ('\n' if out else ''))
    os.chown(tmp, st.st_uid, st.st_gid)
    os.chmod(tmp, 0o600)
    os.replace(tmp, path)
    names = [k.split(' ')[2].replace('eventvox:', '') for k in keys]
    text = (f'{len(keys)} {"sleutel" if len(keys) == 1 else "sleutels"}' + (f' ({", ".join(names)})' if names else '')
            + (f', {skipped} ongeldig' if skipped else '')) if keys or skipped else 'Geen sleutels uit EventVOX'
    result = {'version': version, 'result': text[:200], 'at': datetime.datetime.now().astimezone().isoformat(timespec='seconds')}
    rpath = os.path.join(STATE, 'ssh-result.json')
    with open(rpath + '.tmp', 'w', encoding='utf-8') as f:
        json.dump(result, f)
    os.replace(rpath + '.tmp', rpath)
    try:
        s = os.stat(STATE)
        os.chown(rpath, s.st_uid, s.st_gid)
    except OSError:
        pass
    print(text)
    return 0


if __name__ == '__main__':
    sys.exit(main())
