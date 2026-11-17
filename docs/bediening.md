# Bediening vanuit EventVOX

Een Pi met EventVOX-Pi werkt in EventVOX zoals een Zebra met de kiosk-app. Ga naar **Toegang → Terminals** en open de
terminal.

## Wat je ziet

De kaart **EventVOX-Pi (Raspberry Pi)** op de pagina van de terminal:

- **Raspberry Pi**: het model, de temperatuur en de vrije ruimte op de SD-kaart
- **Versie** van EventVOX-Pi (met *testkanaal* als hij op het testkanaal staat)
- **Netwerk**: of de **kabel** is aangesloten (met snelheid), het **wifi**-netwerk en de sterkte, en via welke van de
  twee de Pi nu **internet** heeft. In de lijst staat daarvoor een label *Kabel* of *Wifi*
- **Stabiliteit**: hoe vaak de browser vastliep en opnieuw startte, en hoe lang de Pi aan staat
- **Laatste update-controle** en de uitkomst
- **Klok**: of de klok van de Pi gelijk loopt met EventVOX

In de lijst krijgt een Pi met een oudere versie een oranje label (*App 1.0.0*); bovenaan staat hoeveel het er zijn, met
**Alle bijwerken**.

## NFC-lezer

Een USB-NFC-lezer werkt op twee manieren:

- **Een lezer die zelf typt** ("keyboard emulation", zoals de ACS ACR1281U-C2 of R80UF): typt het nummer met Enter, net
  als een barcodescanner. Werkt meteen (NumLock staat aan: veel lezers typen hun cijfers op het numerieke toetsenblok).
- **Een gewone kaartlezer** (PC/SC, zoals de veelgebruikte **ACS ACR122U**): die piept alleen. EventVOX-Pi leest het
  nummer zelf uit en typt het met Enter in de scanterminal. Een kaart die op de lezer blijft liggen telt één keer.

De scanterminal herkent een polsbandje ook als het nummer decimaal of in omgekeerde volgorde binnenkomt.

## Onderhoud

Zolang de Pi bijwerkt (*EventVOX-Pi bijwerken*, *Alles bijwerken*, of 's nachts) en vlak voor *Pi herstarten*, staat er **Onderhoud** op het scherm.
Daarna verdwijnt het vanzelf, of start de Pi opnieuw.

## Opdrachten

Op de pagina van de terminal, of voor een selectie in de lijst met **Kiosk-opdracht**. Ze komen binnen een minuut aan
en worden één keer uitgevoerd.

| Opdracht | Wat er gebeurt |
|---|---|
| **Pagina herladen** | De scanterminal laadt opnieuw |
| **App herstarten** | De browser start opnieuw |
| **Pi herstarten** | De hele Pi start opnieuw op (ongeveer een minuut) |
| **EventVOX-Pi bijwerken** | Alleen de nieuwste EventVOX-Pi; daarna starten de agent en de browser opnieuw (de Pi niet) |
| **Alles bijwerken** | De nieuwste EventVOX-Pi en de updates van Raspberry Pi OS en Chromium; daarna herstart de Pi, alleen als er iets nieuws was |
| **Zoek mij** | 30 seconden een knipperend scherm en piepen via het scherm; een tik of toets stopt het. Een Pi heeft geen GPS: geen locatie |
| **Koppelen met Connect** | Zie hieronder |
| **Ontkoppelen van Connect** | De Pi verdwijnt uit je Raspberry Pi Connect-account |

## Raspberry Pi Connect koppelen vanuit EventVOX

Je kunt een Pi ook ná het inrichten aan [Raspberry Pi Connect](https://connect.raspberrypi.com) koppelen, zonder auth key:

1. Open de terminal in EventVOX. Bij *Raspberry Pi Connect* staat *niet gekoppeld*: klik op **Koppelen met Connect**.
2. Binnen een minuut verschijnt een koppellink (`connect.raspberrypi.com/verify/…`). Open hem, log in bij Raspberry Pi
   Connect en keur de Pi goed.
3. Daarna staat er *gekoppeld* en zie je de Pi in Connect.

De link is 15 minuten geldig. Wie hem als eerste goedkeurt, krijgt de Pi in zijn account: deel hem niet. EventVOX toont
hem alleen aan wie kiosk-opdrachten mag geven, en hij komt niet in het logboek.

## Wifi uit EventVOX

In de admin-tenant van EventVOX (**Platform → Alle terminals → Wifi-netwerken voor de terminals**) beheer je
wifi-netwerken voor alle organisaties of voor gekozen organisaties. Een Pi zet ze binnen een minuut zelf
(NetworkManager), en haalt een netwerk weg als het in EventVOX verwijderd wordt. Netwerken die je in Raspberry Pi Imager
of met de hand instelde, blijven altijd staan. De kaart van de terminal toont bij *Wifi uit EventVOX* welke netwerken
erop staan. Wachtwoorden komen nooit in het logboek.

## Inloggen met SSH

In de admin-tenant van EventVOX (**Platform → Alle terminals → SSH-sleutels voor de Raspberry Pi's**) zet je de
**publieke** SSH-sleutels van de beheerders. Elke Pi laat die binnen een minuut binnen, zonder wachtwoord:

```bash
ssh <gebruiker>@<naam van de Pi>.local      # de gebruiker uit Raspberry Pi Imager
```

Een verwijderde sleutel verdwijnt van alle Pi's. Een sleutel die je in Raspberry Pi Imager opgaf, blijft altijd staan.
Nog geen sleutel? Maak er een op je eigen computer met `ssh-keygen -t ed25519` en plak de inhoud van
`~/.ssh/id_ed25519.pub` in EventVOX (nooit het bestand zonder `.pub`: dat is je privésleutel). Zonder netwerk in de buurt
kan het ook via Raspberry Pi Connect (*Remote shell*), zonder sleutel of wachtwoord.

## Diagnose

**Diagnose opvragen** haalt het logboek van de Pi op (opstarten, opdrachten, bijwerken, browsercrashes, temperatuur,
schijfruimte). Er staan geen wachtwoorden of gescande codes in.

## Kiosk-instellingen

Een Pi gebruikt van de kiosk-instellingen alleen:

| Instelling | Standaard |
|---|---|
| **Kanaal** | Stabiel (*Test*: ook pre-releases) |
| **Automatisch bijwerken** | Uit (vanaf 0.0.13); aan: 's nachts alles bijwerken |
| **'s Nachts herladen** | Aan: 's nachts de browser opnieuw starten (geheugen) |
| **Herladen om** | 04:00 |

De rest (NFC, trillen, volume, dimmen) is voor een Zebra. 's Nachts gebeurt alleen iets als er 5 minuten niet gescand is.
