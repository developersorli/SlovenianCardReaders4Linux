---
title: "Kako na Ubuntuju uporabljati slovensko e-kartico — v 5 minutah"
date: 2026-09-21
author: developersorli
tags: [linux, ubuntu, eid, pametna kartica, odprtokodno]
description: "S tem odprtokodnim projektom je končno mogoče uporabljati slovensko e-identiteto v Firefoxu na Linuxu — brez Windowsa."
---

# Kako na Ubuntuju uporabljati slovensko e-kartico — v 5 minutah

## Zgodba za začetek

Lani sem naletel na težavo, ki bo znana marsikateremu uporabniku Linuxa v Sloveniji: potreboval sem digitalno potrdilo za podpis dokumenta, a je bil edini način za njegovo uporabo — Windows. Nameščen sem imel Ubuntu, z e-identiteto pa bi rad dostopal do e-uprave, elektronsko podpisoval pogodbe in se prijavljal v sisteme e-zdravja. Rešitev? **Dvojni sistem**.

Pozneje sem odkril projekt [SlovenianCardReaders4Linux](https://github.com/developersorli/SlovenianCardReaders4Linux) — odprtokodno orodje, ki avtomatizira vse za uporabo slovenske eID kartice v Firefoxu na Linuxu. In zdaj sem to zgodbo hotel deliti naprej.

---

## Kaj vse omogoča slovenska e-identiteta?

Slovenska elektronska identiteta (eID) kartica ni samo prijavno geslo — je zmogljivo orodje za digitalne storitve:

| Storitev | Opis |
|---|---|
| **e-uprava** | Prijava na portal e-uprava.si, oddaja vlog, pregled podatkov |
| **e-zdravje** | Dostop do osebnega zdravstvenega portala, recepti, napotnice |
| **Elektronski podpis** | Kvalificirano e-podpisovanje dokumentov (QES) — pravno veljavno |
| **Spletno bančništvo** | Prijava v nekatere banke s kvalificiranim potrdilom |

---

## Kako projekt deluje

Uporaba pametne kartice na Linuxu vključuje več komponent, ki morajo med seboj pravilno sodelovati:

- **USB čitač kartic** — fizična naprava za branje kartice
- **pcscd daemon** — sistemska storitev za komunikacijo s čitačem
- **OpenSC PKCS#11** — programska plast, ki izpostavi certifikate in PIN na kartici
- **Snap Firefox** — brskalnik z vmesniki do sistemskih virov
- **eID vtičnik Firefox** — razširitev za pametne kartice

Projekt avtomatizira povezovanje vseh teh komponent.

---

## Namestitev — varen način korak za korakom

> ⚠️ **Varnostno opozorilo:** Pred zagonom katerekoli skripte iz interneta si vedno oglej njeno vsebino, da se prepričaš, da ne dela ničesar nepričakovanega.

### Korak 1: Prenesi skripto

```bash
wget https://github.com/developersorli/SlovenianCardReaders4Linux/raw/main/install-firefox-eid.sh
```

### Korak 2: Oglej si, kaj počne (ne zaženi!)

```bash
cat install-firefox-eid.sh
```

Preberi vsebino in se prepričaj, da razumeš vsak korak.

### Korak 3: Zaženi

```bash
chmod +x install-firefox-eid.sh
./install-firefox-eid.sh
```

Ali pa en ukaz — a le če si najprej pregledal vsebino skripte:

```bash
curl -sSL https://raw.githubusercontent.com/developersorli/SlovenianCardReaders4Linux/main/install-firefox-eid.sh | bash
```

---

## Kaj namestitvena skripta naredi?

Skripta `install-firefox-eid.sh` pripravi celoten sistem:

| Korak | Kaj se zgodi |
|---|---|
| 1. | Dodajanje uporabnika v skupino `plugdev` (dostop do USB naprav) |
| 2. | Namestitev paketov: `pcscd`, `libccid`, `libpcsclite1`, `pcsc-tools`, `opensc`, `snapd` |
| 3. | Onemogočitev avtomatskega zagona `pcscd` (kartice ni mogoče zlorabiti za prijavo v sistem) |
| 4. | Namestitev Snap Firefoxa in povezava s storitvijo pcscd |
| 5. | Priprava Firefox profila za pametne kartice |
| 6. | Konfiguracija OpenSC — samo visoko-varenstvena eID aplikacija (QES) |

### Shranjevanje na namizje

V repozitoriju najdeš datoteko `StartupServiceCardReader.desktop`. Če jo kopiraš v svoj `$HOME/.local/share/applications/`, lahko dvojni klik nanjo zažene storitev pcscd — brez odpiranja brskalnika. Uporabno, če kartico potrebuješ le za preverjanje podatkov na njej.

---

## Uporaba

Po namestitvi je seja z e-identiteto samo en ukaz:

```bash
./start-firefox-pcscd.sh [URL]
```

Skripta:
1. Zažene storitev `pcscd`
2. Odpre Firefox (z navedenim URL-jem, če ga podaš)
3. Po zaprtju brskalnika ustavi `pcscd`

Kartica je torej »aktivna« le takrat, ko jo dejansko potrebuješ.

---

## Podprti bralniki in kartice

- **Čitači:** kateri koli CCID-kompatibilni USB čitač (GEMPC 420, OmniKey CardMan 3121 …)
- **Kartice:** slovenska eID kartica ali druge PKCS#15 kartice (npr. španski DNIe)

---

## Pogosta vprašanja (FAQ)

**Ali deluje na Fedori / Archu / Manjaro?**
Trenutno je podprt samo Ubuntu in Debian (sistemi z `systemd` in `apt`). Prispevki za druge distribucije so dobrodošli!

**Ali dela v Chrome ali Chromiumu?**
Ne. Projekt trenutno deluje samo s Firefoxom prek Snap vmejevalnika.

**Zakaj je onemogočen avtomatski zagon pcscd?**

Brez tega bi ob vstavljeni kartici ob zagonu sistema `pcscd` prevzel dostop do kartice — uporabnik pa ne bi mogel vnesti gesla za prijavo, ker je zaslon »zaklenjen« s čakalno vrsto pametne kartice. Tudi če kartice ne bi želeli uporabljati za prijavo v sistem (ampak samo npr. za e-podpis), bi bila normalna prijava onemogočena.

Z onemogočitvijo avtomatskega zagona morate storitev `pcscd` eksplicitno zagnati — kar pomeni, da ste vedno vi tisti, ki nadzorujete dostop do kartice. Takrat pa seveda veste, da jo boste potrebovali za e-identiteto.

**Ali potrebujem internetno povezavo vsakič, ko uporabljam kartico?**
Ne. Namestitev je enkratna. Kartica in certifikati so shranjeni na njej — internet potrebuješ samo za dostop do spletnih storitev.

---

## Zaključek

S projektom SlovenianCardReaders4Linux je Linux uporabnikom končno na voljo polna funkcionalnost slovenske e-identitete. Gre za odličen primer skupnosti, ki rešuje vsakodnevne težave in približuje odprtokodne sisteme širši rabi.

💡 Všeč ti je projekt? Podpri ga s ⭐ na GitHubu ali prispevaj k razvoju!

🔗 [Angleška različica članka](./clanek-eng.md)

**Več informacij:** [GitHub repozitorij](https://github.com/developersorli/SlovenianCardReaders4Linux)
