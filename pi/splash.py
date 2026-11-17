#!/usr/bin/env python3
"""
EventVOX-Pi: het EventVOX-logo op het scherm tijdens het opstarten (tot de kiosk het scherm overneemt) en bij afsluiten
of herstarten (eventvox-pi-splash.service).

Bewust zonder risico voor de opstart: geen initramfs, geen config.txt of cmdline.txt. Het logo gaat rechtstreeks naar de
framebuffer (/dev/fb0) zodra Linux draait; lukt iets niet, dan is er gewoon geen logo. Alleen de standaardbibliotheek van
Python. Het logo (pi/logo.tga, 24-bit, ongecomprimeerd) wordt één keer per schermformaat geschaald en omgezet en in
/var/cache/eventvox-pi bewaard, zodat het daarna in een fractie van een seconde op het scherm staat.

Omgeving (tests): EVX_PI_LOGO, EVX_PI_FB (de framebuffer, in tests een bestand), EVX_PI_FB_SYSFS (map met virtual_size,
bits_per_pixel en stride), EVX_PI_SPLASH_CACHE, EVX_PI_TTY (de console; leeg: niet aanraken), EVX_PI_FB_WAIT (seconden).
"""
import hashlib
import os
import struct
import sys
import time

LOGO = os.environ.get('EVX_PI_LOGO') or os.path.join(os.path.dirname(os.path.abspath(__file__)), 'logo.tga')
FB = os.environ.get('EVX_PI_FB') or '/dev/fb0'
SYSFS = os.environ.get('EVX_PI_FB_SYSFS') or '/sys/class/graphics/fb0'
CACHE = os.environ.get('EVX_PI_SPLASH_CACHE') or '/var/cache/eventvox-pi'
TTY = os.environ.get('EVX_PI_TTY', '/dev/tty1')
WAIT = float(os.environ.get('EVX_PI_FB_WAIT', '5'))


def read_tga(path):
    """(breedte, hoogte, rijen van boven naar beneden als bytes RGB) uit een ongecomprimeerde 24-bit TGA"""
    with open(path, 'rb') as f:
        data = f.read()
    id_len, cmap, kind = data[0], data[1], data[2]
    w, h = struct.unpack('<HH', data[12:16])
    bpp, desc = data[16], data[17]
    if kind != 2 or cmap != 0 or bpp != 24:
        raise ValueError('logo: alleen ongecomprimeerde 24-bit TGA')
    start = 18 + id_len
    rows = []
    for y in range(h):
        bgr = data[start + y * w * 3:start + (y + 1) * w * 3]
        rgb = bytearray(len(bgr))
        rgb[0::3], rgb[1::3], rgb[2::3] = bgr[2::3], bgr[1::3], bgr[0::3]
        rows.append(bytes(rgb))
    if not desc & 0x20:  # oorsprong linksonder: omdraaien
        rows.reverse()
    return w, h, rows


def fb_info():
    """(breedte, hoogte, bits per pixel, bytes per rij) van de framebuffer"""
    def read(name):
        with open(os.path.join(SYSFS, name)) as f:
            return f.read().strip()
    w, h = (int(x) for x in read('virtual_size').split(','))
    bpp = int(read('bits_per_pixel'))
    try:
        stride = int(read('stride'))
    except (OSError, ValueError):
        stride = w * bpp // 8
    return w, h, bpp, stride


def pixel_format(bpp):
    """Een functie (r, g, b) -> bytes voor de framebuffer (little-endian, zoals op de Pi)"""
    if bpp == 32:
        return lambda r, g, b: bytes((b, g, r, 0))
    if bpp == 24:
        return lambda r, g, b: bytes((b, g, r))
    if bpp == 16:
        return lambda r, g, b: struct.pack('<H', (r >> 3) << 11 | (g >> 2) << 5 | b >> 3)
    raise ValueError(f'framebuffer met {bpp} bits per pixel')


def render(logo, fb):
    """Het hele scherm: het logo zo groot mogelijk in het midden, de rest in de achtergrondkleur van het logo"""
    lw, lh, rows = logo
    w, h, bpp, stride = fb
    conv_px = pixel_format(bpp)
    size = bpp // 8
    conv = {}

    def px(rgb):
        out = conv.get(rgb)
        if out is None:
            out = conv[rgb] = conv_px(rgb[0], rgb[1], rgb[2])
        return out

    bg = px(rows[0][0:3])
    scale = min(w / lw, h / lh)
    sw, sh = max(1, int(lw * scale)), max(1, int(lh * scale))
    x0, y0 = (w - sw) // 2, (h - sh) // 2
    cols = [min(lw - 1, int(x / scale)) * 3 for x in range(sw)]
    pad = b'\0' * (stride - w * size)
    empty = bg * w + pad
    left, right = bg * x0, bg * (w - sw - x0)
    lines = {}
    out = []
    for y in range(h):
        if y < y0 or y >= y0 + sh:
            out.append(empty)
            continue
        sy = min(lh - 1, int((y - y0) / scale))
        line = lines.get(sy)
        if line is None:
            row = rows[sy]
            line = lines[sy] = left + b''.join(px(row[c:c + 3]) for c in cols) + right + pad
        out.append(line)
    return b''.join(out)


def frame():
    """Het scherm voor deze framebuffer, uit de cache of nu gemaakt (en bewaard)"""
    fb = fb_info()
    st = os.stat(LOGO)
    key = hashlib.sha1(f'{fb}|{st.st_size}|{int(st.st_mtime)}'.encode()).hexdigest()[:16]
    cached = os.path.join(CACHE, f'splash-{fb[0]}x{fb[1]}-{fb[2]}-{key}.raw')
    try:
        with open(cached, 'rb') as f:
            data = f.read()
        if len(data) == fb[3] * fb[1]:
            return data
    except OSError:
        pass
    data = render(read_tga(LOGO), fb)
    try:
        os.makedirs(CACHE, exist_ok=True)
        for old in os.listdir(CACHE):
            if old.startswith('splash-'):
                os.remove(os.path.join(CACHE, old))
        with open(cached + '.tmp', 'wb') as f:
            f.write(data)
        os.replace(cached + '.tmp', cached)
    except OSError:
        pass  # zonder cache: volgende keer opnieuw rekenen
    return data


def quiet_console():
    """Geen knipperende cursor en geen tekst over het logo (de console schrijft zwart op zwart)"""
    try:
        with open('/sys/class/graphics/fbcon/cursor_blink', 'w') as f:
            f.write('0')
    except OSError:
        pass
    if TTY:
        try:
            with open(TTY, 'w') as f:
                f.write('\033[?25l\033[30;40m')
        except OSError:
            pass


def main():
    deadline = time.time() + WAIT
    while not os.path.exists(FB) or not os.path.exists(os.path.join(SYSFS, 'virtual_size')):
        if time.time() > deadline:
            print('Geen framebuffer: geen logo')
            return 0
        time.sleep(0.2)
    try:
        data = frame()
        quiet_console()
        with open(FB, 'r+b') as f:
            f.write(data)
    except (OSError, ValueError) as e:
        print(f'Logo tonen lukte niet: {e}')  # nooit een fout: de Pi start gewoon, zonder logo
    return 0


if __name__ == '__main__':
    sys.exit(main())
