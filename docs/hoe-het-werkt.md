# Hoe het werkt

```
 scherm ── labwc ── Chromium (kiosk) ── scanterminal van EventVOX ── heartbeat ──► EventVOX
                       │ debugpoort 127.0.0.1:9222        ▲ window.WebKiosk
                       ▼                                  │
                    agent.py ──────────────────────────────┘
                       │ sudo (alleen reboot, update, wifi en ssh)
                       ▼
                 eventvox-pi-root ──► systemctl reboot / eventvox-pi-update.service (update.sh) / wifi.py (nmcli) / ssh.py
```

- **labwc** (Wayland) start na het automatisch inloggen op het scherm en start **`kiosk.sh`**: Chromium als kiosk op de
  scanterminal, met het serienummer in het adres. Stopt Chromium, dan start hij binnen een paar seconden opnieuw (een
  onverwachte stop telt als crash).
- De **agent** (`agent.py`, gebruikersdienst `eventvox-pi-agent`) verbindt met de debugpoort van Chromium. Die luistert
  alleen op de Pi zelf, niet op het netwerk. De agent zet in de scanterminal `window.WebKiosk` (`bridge.js`): dezelfde
  koppeling als de kiosk-app op een Zebra. De scanterminal geeft daarmee bij elke heartbeat de staat van de Pi mee aan
  EventVOX, en geeft opdrachten en instellingen uit EventVOX door aan de agent.
- Herstarten, bijwerken, wifi en SSH-sleutels gaan als root via **`eventvox-pi-root`**, het enige wat de agent met sudo mag.
- **`ssh.py`** zet de SSH-sleutels uit EventVOX in een eigen blok van `~/.ssh/authorized_keys`; andere sleutels blijven.
- **`wifi.py`** zet de wifi-netwerken uit EventVOX (verbindingen `evx-…` in NetworkManager). De lijst komt via stdin,
  nooit in een bestand; het script controleert hem streng en raakt alleen zijn eigen `evx-`-verbindingen aan.
- **`update.sh`** werkt bij (zie [bijwerken](bijwerken-en-releases.md)).

## Op de Pi

| Pad | Wat |
|---|---|
| `/opt/eventvox-pi/` | `agent.py`, `bridge.js`, `locate.js` (Zoek mij), `kiosk.sh`, `update.sh`, `cleanup.sh` (wekelijks opruimen), `wifi.py`, `ssh.py`, `VERSION` (alles van root, niet te wijzigen door de kiosk-gebruiker) |
| `/usr/local/sbin/eventvox-pi-root` | Herstarten, bijwerken, wifi en SSH-sleutels als root |
| `/etc/eventvox-pi/config` | Het adres (`URL`), de kiosk-gebruiker (`KIOSK_USER`) en eventueel `HDMI_AUDIO=0` (geluid niet naar HDMI) |
| `/var/lib/eventvox-pi/` | De staat: uitgevoerde opdrachten, instellingen uit EventVOX, `log.txt`, de uitkomst van het bijwerken en van wifi (zonder wachtwoorden) |
| `~/.config/eventvox-kiosk/` | Het Chromium-profiel (hier bewaart de scanterminal zijn koppeling met EventVOX) |
| `/etc/sudoers.d/eventvox-pi` | Wat de agent als root mag |

## Wat het installatiescript nog meer doet

- Geen vertaalbalk, inlog- of wachtwoordvragen in Chromium (policy)
- Een rustige opstart: geen Linux-tekst en geen logo's van Raspberry Pi (geen eigen opstartlogo: dat vroeg een nieuwe
  initramfs, en daarmee startten Pi's niet op)
- NumLock aan in labwc (veel NFC-lezers en scanners typen hun cijfers op het numerieke toetsenblok)
- Geen meldingen op het scherm, het scherm gaat nooit uit, geluid via HDMI (`kiosk.sh` kiest bij elke start
  de HDMI-geluidskaart van het aangesloten scherm)
- Eigen naam en SSH-sleutels per Pi (`eventvox-<serienummer>`), ook als je een SD-kaart kloont
- Automatische beveiligingsupdates
- **Onderhoud** (ook bij bijwerken):
  - elke week, in de nacht van zondag op maandag (`eventvox-pi-cleanup.timer`, `cleanup.sh`): oude pakketten en
    apt-downloads, crashdumps, tijdelijke bestanden ouder dan een week en oude logboeken weg; de uitkomst staat in de
    Diagnose (*Onderhoud*);
  - **minder schrijven naar de SD-kaart** (de kaart gaat langer mee): het systeemlogboek en de cache van Chromium staan in
    het geheugen, niet op de kaart; na een herstart is het systeemlogboek weg (het logboek voor de Diagnose blijft). `/tmp`
    staat al in het geheugen en Raspberry Pi OS schrijft geen leestijden (`noatime`);
  - na het bijwerken de gedownloade pakketten weg;
  - diensten die een kiosk niet gebruikt uit (ModemManager, printen) en `cloud-init` na de eerste start; Bluetooth blijft
    aan (voor Bluetooth-scanners);
  - Chromium: cache hoogstens 32 MB (in het geheugen), geen eigen onderdelen-updates op de achtergrond.
- Wat het bewust **niet** doet: overklokken, `config.txt`, `cmdline.txt` of de initramfs wijzigen bij bijwerken. De SD-kaart
  vergroot Raspberry Pi OS zelf bij de eerste start tot de hele kaart; in EventVOX zie je vrije ruimte en totaal.
- Raspberry Pi Connect
