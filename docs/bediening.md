# Bediening vanuit EventVOX

Een Pi met EventVOX-Pi werkt in EventVOX zoals een Zebra met de kiosk-app. Ga naar **Toegang → Terminals** en open de
terminal.

## Wat je ziet

De kaart **EventVOX-Pi (Raspberry Pi)** op de pagina van de terminal:

- **Raspberry Pi**: het model, de temperatuur en de vrije ruimte op de SD-kaart
- **Versie** van EventVOX-Pi (met *testkanaal* als hij op het testkanaal staat)
- **Wifi**: netwerk en sterkte (niet bij een kabel)
- **Stabiliteit**: hoe vaak de browser vastliep en opnieuw startte, en hoe lang de Pi aan staat
- **Laatste update-controle** en de uitkomst
- **Klok**: of de klok van de Pi gelijk loopt met EventVOX

In de lijst krijgt een Pi met een oudere versie een oranje label (*App 1.0.0*); bovenaan staat hoeveel het er zijn, met
**Alle bijwerken**.

## Opdrachten

Op de pagina van de terminal, of voor een selectie in de lijst met **Kiosk-opdracht**. Ze komen binnen een minuut aan
en worden één keer uitgevoerd.

| Opdracht | Wat er gebeurt |
|---|---|
| **Pagina herladen** | De scanterminal laadt opnieuw |
| **App herstarten** | De browser start opnieuw |
| **Pi herstarten** | De hele Pi start opnieuw op (ongeveer een minuut) |
| **Nu bijwerken** | De nieuwste EventVOX-Pi en de updates van de Pi zelf; daarna herstart hij, alleen als er iets nieuws was |
| **Zoek mij** | 30 seconden een knipperend scherm en piepen via het scherm; een tik of toets stopt het. Een Pi heeft geen GPS: geen locatie |

## Diagnose

**Diagnose opvragen** haalt het logboek van de Pi op (opstarten, opdrachten, bijwerken, browsercrashes, temperatuur,
schijfruimte). Er staan geen wachtwoorden of gescande codes in.

## Kiosk-instellingen

Een Pi gebruikt van de kiosk-instellingen alleen:

| Instelling | Standaard |
|---|---|
| **Kanaal** | Stabiel (*Test*: ook pre-releases) |
| **Automatisch bijwerken** | Aan: 's nachts bijwerken |
| **'s Nachts herladen** | Aan: 's nachts de browser opnieuw starten (geheugen) |
| **Herladen om** | 04:00 |

De rest (NFC, trillen, volume, dimmen) is voor een Zebra. 's Nachts gebeurt alleen iets als er 5 minuten niet gescand is.
