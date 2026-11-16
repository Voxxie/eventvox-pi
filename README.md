# EventVOX-Pi

Maakt van een **Raspberry Pi** (3B of nieuwer) een vaste **EventVOX-scanterminal**: bij het aanzetten opent hij
schermvullend de scanterminal van EventVOX, zonder meldingen of popups. Een USB-scanner werkt als toetsenbord.
EventVOX ziet de Pi en kan hem **op afstand bedienen**, net als een Zebra met de kiosk-app
[EventVOX-Webkiosk](https://github.com/Voxxie/eventvox-kioskapp): herladen, herstarten, bijwerken, Zoek mij en diagnose.
Hij werkt zichzelf 's nachts bij, en met **Raspberry Pi Connect** kijk je op afstand mee.

## Snel aan de slag

1. Flash een SD-kaart met **Raspberry Pi Imager**: *Raspberry Pi OS Lite*. Stel een gebruiker, wifi (of gebruik een
   kabel) en SSH in.
2. Start de Pi, log in (SSH of toetsenbord) en installeer:
   ```bash
   curl -fsSLO https://github.com/Voxxie/eventvox-pi/releases/latest/download/install.sh
   sudo bash install.sh
   sudo reboot
   ```
3. Het scherm toont een code van 6 tekens: koppel de terminal in EventVOX via **Toegang → Terminals → Terminal koppelen**.

Uitgebreid, met Raspberry Pi Connect: **[docs/inrichten.md](docs/inrichten.md)**.

## Handleiding

| | |
|---|---|
| [Inrichten](docs/inrichten.md) | Een nieuwe Pi klaarmaken, met Raspberry Pi Connect en opties |
| [Bediening vanuit EventVOX](docs/bediening.md) | Wat je in EventVOX ziet en kunt: opdrachten, instellingen, diagnose |
| [Bijwerken en releases](docs/bijwerken-en-releases.md) | Hoe de Pi zichzelf bijwerkt, kanalen, een nieuwe versie uitbrengen |
| [Hoe het werkt](docs/hoe-het-werkt.md) | De onderdelen op de Pi en hoe ze samenwerken |
| [Problemen oplossen](docs/problemen.md) | Zwart scherm, geen verbinding, Connect, logboek |

## In deze repository

| Pad | Wat |
|---|---|
| `install.sh` | Het installatiescript (ook bij elke release te downloaden) |
| `pi/` | Wat op de Pi in `/opt/eventvox-pi` komt: de agent, de browser-start, bijwerken |
| `docs/` | De handleiding |
| `tests/` | Controles zonder Pi (`tests/run.sh`, ook in GitHub Actions) |
| `.github/workflows/` | Controle bij elke push; een release maakt het pakket en `update.json` |

Deze repository is **openbaar**: de Pi's downloaden hun updates hier zonder inloggen. Zet er nooit wachtwoorden,
wifi-sleutels of auth keys in.
