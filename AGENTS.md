# EventVOX-Pi: instructies voor agents

Een Raspberry Pi als EventVOX-scanterminal (`https://eventvox.nl/scanterminal/?serial=…`, Voxxie/eventvox-frontend
`public/scanterminal/`), op afstand te zien en te bedienen vanuit EventVOX. Teksten voor gebruikers en commentaar in de code
zijn **Nederlands**. Handleiding: `docs/` (werk die bij bij elke zichtbare wijziging).

## Harde regels
1. **Openbaar**: nooit wachtwoorden, wifi-sleutels, Connect auth keys of tokens in git, ook niet als voorbeeld.
2. **`update.json`** blijft op dezelfde plek (`releases/latest/download/update.json`, `releases/download/beta/update.json`)
   en in hetzelfde formaat `{ versionCode, versionName, url, sha256, notes }`: velden erbij mag, eruit of hernoemen nooit.
3. **versionCode stijgt altijd**: tag `vMAJOR.MINOR.PATCH` (MINOR, PATCH 0–99) → `MAJOR*10000+MINOR*100+PATCH`. Lokaal
   `0.0.0-dev` (0).
4. **Elke oudere versie werkt rechtstreeks bij naar de nieuwste**: `pi/update.sh` van een oude versie pakt het pakket uit
   en draait `eventvox-pi/install.sh --update` daaruit. Houd die indeling van het pakket (`release.yml`) en die aanroep
   werkend; `--update` behoudt `/etc/eventvox-pi/config` en `/var/lib/eventvox-pi` (oude sleutels in `state.json` blijven
   geldig, ontbrekende krijgen een standaard).
5. **`window.WebKiosk`** (`pi/bridge.js`) volgt het contract van de kiosk-app (Voxxie/eventvox-kioskapp, AGENTS.md):
   alleen toevoegen. `getStatus()` geeft `app: 'pi'` en `pi { model, temperature_c, undervoltage, undervoltage_seen,
   throttled, disk_free_mb, disk_total_mb }`, `ethernet { connected, speed_mbps }` en `uplink` (`ethernet`|`wifi`); `getNetwork()` geeft `{ uplink, ethernet }` (de scanterminal toont via de kabel een kabel-icoon). De backend (`Helpers\Terminals::kioskStatus`) laat onbekende velden vallen: een nieuw veld
   eerst daar, dan in de frontend. Ook `wifi_version` (altijd, ook leeg) en `wifi_result`; `setWifiProfiles(json)` zet de
   wifi-netwerken uit EventVOX; `ssh_version`/`ssh_result` en `setSshKeys(json)` de SSH-sleutels van de beheerders. Opdrachten: `reload`, `restart` (browser), `reboot`, `update` (alles: EventVOX-Pi en apt, herstart bij iets nieuws), `update_app` (alleen EventVOX-Pi: agent en browser opnieuw, geen herstart), `locate`, `refresh_screen` (Scherm opfrissen, `pi/refresh.js`), `connect_signin`, `connect_signout`.
   `connect { installed, signed_in, verify_url?, verify_until? }`: Raspberry Pi Connect; de koppellink alleen zolang hij
   op goedkeuring wacht en nooit in het logboek.
6. Root alleen via `pi/eventvox-pi-root` (`reboot`, `update`, `update-app`, `wifi`, `ssh`). Nachtelijk bijwerken (`auto_update`) staat standaard uit. `ssh` (`pi/ssh.py`): alleen publieke sleutels
   zonder opties, in een eigen blok van authorized_keys; sleutels daarbuiten nooit aanraken. `wifi` leest de netwerken uit EventVOX van stdin
   (`pi/wifi.py`: strenge controle, nmcli zonder shell, alleen eigen `evx-`-verbindingen); nooit wachtwoorden in een
   bestand of logboek. Bestanden in `/opt/eventvox-pi` zijn van root. De debugpoort van Chromium alleen op 127.0.0.1.
7. Geen locatie (een Pi heeft geen GPS en dat blijft zo), geen geheimen of gescande codes in het logboek.
8. Onderspanning (`undervoltage`, `undervoltage_seen`, `throttled`) staat in EventVOX op de terminalpagina bij *Voeding* (frontend `piPowerText`).

## Opbouw
| Pad | Wat |
|---|---|
| `install.sh` | Installeren (root); los gedownload haalt hij eerst het pakket van de nieuwste release |
| `pi/agent.py` | De agent: Chrome DevTools Protocol (eigen kleine websocket, standaardbibliotheek van Python 3); leest ook NFC-lezers zonder toetsenbord-modus (PC/SC, pyscard) en typt het nummer als toetsaanslagen + Enter (de scanterminal leest `keydown`) |
| `pi/bridge.js` / `pi/locate.js` / `pi/maintenance.js` / `pi/refresh.js` | `window.WebKiosk` in de scanterminal / Zoek mij / Onderhoud op het scherm (tijdens bijwerken en voor herstarten) / Scherm opfrissen |
| `pi/kiosk.sh` | Chromium-lus (labwc autostart) |
| `pi/splash.py` / `pi/logo.tga` | Het logo bij opstarten en afsluiten, rechtstreeks op de framebuffer (`eventvox-pi-splash.service`), met een voortgangsbalk naar de vorige opstartduur (`--progress`, eigen dienst die niets ophoudt). Nooit via de initramfs, `config.txt` of `cmdline.txt` (0.0.6 tot 0.0.9 startten daardoor niet) |
| `pi/update.sh` | Bijwerken: pakket (SHA-256) en apt; herstart alleen als er iets nieuws was |
| `pi/cleanup.sh` | Wekelijks opruimen als root (`eventvox-pi-cleanup.timer`); raakt nooit de opstart, instellingen of het Chromium-profiel (behalve crashrapporten) |
| `pi/wifi.py` | Wifi-netwerken uit EventVOX zetten (als root, nmcli) |
| `pi/ssh.py` | SSH-sleutels uit EventVOX in authorized_keys (als root) |
| `image/` | Het SD-kaart-image (`qemu-test.sh`: opstarttest in een nagebootste Pi 3B, in `image.yml` vóór het uploaden; `build.sh`: officieel Raspberry Pi OS Lite 64-bit + pakketten + `/opt/eventvox-pi-kit`; `firstboot.sh`: wacht op gebruiker uit Imager, `install.sh --firstboot`, herstart; `manifest.py`: beschrijving voor Imager met `init_format` van het basis-image). Workflow `image.yml` (arm64-runner). |
| `tests/` | `run.sh`: shellcheck, `update.test.sh`, `wifi.test.sh`, `ssh.test.sh`, `cleanup.test.sh`, `firstboot.test.sh`, `install-connect.test.sh`, `splash.test.sh`, `agent.test.mjs` |

## Testen
Er is geen Pi: test wat kan (`tests/run.sh`, ook in CI) en zeg eerlijk wat alleen op een Pi te testen is (labwc, HDMI,
Connect, echt herstarten en apt). `FRONTEND=/pad/naar/eventvox-frontend tests/run.sh` test de agent ook tegen de echte
scanterminal.
