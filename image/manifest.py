#!/usr/bin/env python3
"""
De beschrijving van het EventVOX-Pi-image voor Raspberry Pi Imager (os_list, zoals de officiële lijst), zodat Imager de
instellingen (gebruiker, wifi, SSH, Raspberry Pi Connect) toepast. Neemt init_format, capabilities en devices over van
het basis-image uit de officiële lijst: het image start op dezelfde manier.

  image/manifest.py <basis-entry.json> <versie> <image.img.xz> <image.img.xz.extract> <download-URL> > eventvox-pi.json
"""
import datetime
import hashlib
import json
import os
import sys

base_file, version, xz_path, extract_path, url = sys.argv[1:6]
base = json.load(open(base_file))
extract_size, extract_sha = open(extract_path).read().split()
sha = hashlib.sha256()
with open(xz_path, 'rb') as f:
    for chunk in iter(lambda: f.read(1 << 20), b''):
        sha.update(chunk)
entry = {
    'name': f'EventVOX-Pi {version}',
    'description': 'EventVOX-scanterminal op een Raspberry Pi (Raspberry Pi OS Lite met EventVOX-Pi). Stel gebruiker en wifi '
                   'in, start de Pi en koppel de code in EventVOX.',
    'url': url,
    'icon': base.get('icon', ''),
    'website': 'https://github.com/Voxxie/eventvox-pi',
    'release_date': datetime.date.today().isoformat(),
    'extract_size': int(extract_size),
    'extract_sha256': extract_sha,
    'image_download_size': os.path.getsize(xz_path),
    'image_download_sha256': sha.hexdigest(),
    'devices': base.get('devices', []),
    'init_format': base.get('init_format', 'none'),
}
for key in ('capabilities', 'architecture'):
    if key in base:
        entry[key] = base[key]
json.dump({'os_list': [entry]}, sys.stdout, indent=2)
print()
