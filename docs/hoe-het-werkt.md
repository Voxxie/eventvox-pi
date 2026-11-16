# Hoe het werkt

```
 scherm ── labwc ── Chromium (kiosk) ── scanterminal van EventVOX ── heartbeat ──► EventVOX
                       │ debugpoort 127.0.0.1:9222        ▲ window.WebKiosk
                       ▼                                  │
                    agent.py ──────────────────────────────┘
                       │ sudo (alleen reboot en update)
                       ▼
                 eventvox-pi-root ──► systemctl reboot / eventvox-pi-update.service (update.sh)
```

- **labwc** (Wayland) start na het automatisch inloggen op het scherm en start **`kiosk.sh`**: Chromium als kiosk op de
  scanterminal, met het serienummer in het adres. Stopt Chromium, dan start hij binnen een paar seconden opnieuw (een
  onverwachte stop telt als crash).
- De **agent** (`agent.py`, gebruikersdienst `eventvox-pi-agent`) verbindt met de debugpoort van Chromium. Die luistert
  alleen op de Pi zelf, niet op het netwerk. De agent zet in de scanterminal `window.WebKiosk` (`bridge.js`): dezelfde
  koppeling als de kiosk-app op een Zebra. De scanterminal geeft daarmee bij elke heartbeat de staat van de Pi mee aan
  EventVOX, en geeft opdrachten en instellingen uit EventVOX door aan de agent.
- Herstarten en bijwerken gaan als root via **`eventvox-pi-root`**, het enige wat de agent met sudo mag.
- **`update.sh`** werkt bij (zie [bijwerken](bijwerken-en-releases.md)).

## Op de Pi

| Pad | Wat |
|---|---|
| `/opt/eventvox-pi/` | `agent.py`, `bridge.js`, `locate.js` (Zoek mij), `kiosk.sh`, `update.sh`, `VERSION` |
| `/usr/local/sbin/eventvox-pi-root` | Herstarten en bijwerken als root |
| `/etc/eventvox-pi/config` | Het adres (`URL`) en de kiosk-gebruiker (`KIOSK_USER`) |
| `/var/lib/eventvox-pi/` | De staat: uitgevoerde opdrachten, instellingen uit EventVOX, `log.txt`, de uitkomst van het bijwerken |
| `~/.config/eventvox-kiosk/` | Het Chromium-profiel (hier bewaart de scanterminal zijn koppeling met EventVOX) |
| `/etc/sudoers.d/eventvox-pi` | Wat de agent als root mag |

## Wat het installatiescript nog meer doet

- Geen vertaalbalk, inlog- of wachtwoordvragen in Chromium (policy)
- Geen opstartlogo of meldingen op het scherm, het scherm gaat nooit uit, geluid via HDMI
- Eigen naam en SSH-sleutels per Pi (`eventvox-<serienummer>`), ook als je een SD-kaart kloont
- Automatische beveiligingsupdates
- Raspberry Pi Connect
