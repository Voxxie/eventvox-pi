# EventVOX-Pi

Maakt van een **Raspberry Pi** (3B of nieuwer) een vaste **EventVOX-scanterminal**: bij het aanzetten opent hij
schermvullend de scanterminal van EventVOX, zonder meldingen of popups. Een USB-scanner werkt als toetsenbord.
EventVOX ziet de Pi en kan hem **op afstand bedienen**, net als een Zebra met de kiosk-app
[EventVOX-Webkiosk](https://github.com/Voxxie/eventvox-kioskapp): herladen, herstarten, bijwerken, Zoek mij en diagnose.
Hij werkt zichzelf 's nachts bij, en met **Raspberry Pi Connect** kijk je op afstand mee.

## Snel aan de slag

1. Open in **Raspberry Pi Imager 2** de beschrijving van EventVOX-Pi: download
   [`eventvox-pi.rpi-imager-manifest`](https://github.com/Voxxie/eventvox-pi/releases/latest/download/eventvox-pi.rpi-imager-manifest)
   en dubbelklik erop.
2. Kies **EventVOX-Pi**, stel een gebruiker, wifi en eventueel Raspberry Pi Connect in, en schrijf de SD-kaart.
3. Zet de Pi aan. Na een paar minuten (en één herstart) staat er een code van 6 tekens op het scherm: koppel de terminal
   in EventVOX via **Toegang → Terminals → Terminal koppelen**.

Uitgebreid, en de manier met het installatiescript voor een Pi die al draait: **[docs/inrichten.md](docs/inrichten.md)**.

**Geen Pi maar een gewone pc?** Installeer Debian 13 (trixie) zonder bureaublad en draai hetzelfde `install.sh`: zie
[docs/inrichten.md, Op een gewone pc](docs/inrichten.md#op-een-gewone-pc-debian).

## Handleiding

| | |
|---|---|
| [Inrichten](docs/inrichten.md) | Een nieuwe Pi klaarmaken, met Raspberry Pi Connect en opties; ook op een gewone pc (Debian) |
| [Bediening vanuit EventVOX](docs/bediening.md) | Wat je in EventVOX ziet en kunt: opdrachten, instellingen, diagnose |
| [Bijwerken en releases](docs/bijwerken-en-releases.md) | Hoe de Pi zichzelf bijwerkt, kanalen, een nieuwe versie uitbrengen |
| [Hoe het werkt](docs/hoe-het-werkt.md) | De onderdelen op de Pi en hoe ze samenwerken |
| [Problemen oplossen](docs/problemen.md) | Zwart scherm, geen verbinding, Connect, logboek |

## In deze repository

| Pad | Wat |
|---|---|
| `install.sh` | Het installatiescript (ook bij elke release te downloaden) |
| `image/` | Het kant-en-klare SD-kaart-image: bouwen (`build.sh`), eerste start (`firstboot.sh`), beschrijving voor Imager (`manifest.py`) |
| `pi/` | Wat op de Pi in `/opt/eventvox-pi` komt: de agent, de browser-start, bijwerken |
| `docs/` | De handleiding |
| `tests/` | Controles zonder Pi (`tests/run.sh`, ook in GitHub Actions) |
| `.github/workflows/` | Controle bij elke push; een release maakt het pakket, `update.json` en het image |

Deze repository is **openbaar**: de Pi's downloaden hun updates hier zonder inloggen. Zet er nooit wachtwoorden,
wifi-sleutels of auth keys in.
