# SlovenianCardReaders4Linux

Angleška različica: [README.md](README.md)

Dve shell skripti, ki pripravita Ubuntu/Debian sistem za uporabo **slovenskega osebnega izkaznika s čipom** (elektronska identiteta, eID) z USB bralnikom kartic v brskalniku **Firefox**. Enaka nastavitev deluje tudi z drugimi PKCS#15 karticami, npr. španskim DNIe.

## Kaj je to?

Uporaba pametne kartice na Linuxu zahteva več sestavnih delov:

- **pcscd** — PC/SC demon, ki komunicira z USB bralnikom kartic (prek `libccid`)
- **OpenSC** — PKCS#11 vmesnik, ki aplikacijam izpostavi certifikate in PIN kode s kartice
- **Firefox (snap)** — aplikacija v snap omejitvi, ki do pcscd dostopa le prek eksplicitne snap povezave

Projekt to samodejno uredi:

| Skripta | Namen |
|---|---|
| `install-firefox-eid.sh` | Enkratna nastavitev sistema (paketi, uporabniške skupine, Snap Firefox, OpenSC konfiguracija) |
| `start-firefox-pcscd.sh` | Upravlja eID sejo: zagon pcscd → zagon Firefoxa → ugasnitev pcscd ob zaprtju |

### Zakaj ročno upravljanje pcscd?

Če je `pcscd` omogočen za samodejni zagon in je ob zagonu sistema vstavljena eID kartica, se prijava v sistem lahko opravi s **kartico** namesto gesla. Zato skripte `pcscd` zaganjajo in ugašajo samo okoli Firefox seje — kartica je "aktivna" le, medtem ko jo res potrebuješ.

### Kaj se nastavi?

- Uporabnik se doda v skupino `plugdev` (dostop do USB naprav)
- Namestijo se potrebni paketi: `pcscd`, `libccid`, `libpcsclite1`, `pcsc-tools`, `opensc`, `snapd`
- Namesti se Snap Firefox in poveže s pcscd (`sudo snap connect firefox:pcscd`)
- Pripravi se Firefox profil za pametne kartice (OpenSC PKCS#11 modul, dodan v bazo modulov profila `pkcs11.txt`; po želji omogočeni enterprise roots — zaupanje sistemskim korenskim potrdilom)
- OpenSC se konfigurira tako, da je na voljo samo **visoko-varnostna** eID aplikacija (QES — "Podpis in prijava"); nizko-varnostna ("Prijava brez PIN-a", AID `E828BD080F014E585031`) se onemogoči. Pred spremembo se originalna datoteka `/etc/opensc/opensc.conf` shrani kot backup.

## Zahteve

- Ubuntu ali Debian (systemd + apt)
- Podpora za Snap (`snapd`)
- CCID-kompatibilen USB bralnik pametnih kartic (npr. GEMPC 420, OmniKey CardMan 3121)
- Slovenski osebni izkaznik s čipom (eID) ali druga PKCS#15 kartica (npr. DNIe)

## Navodila za uporabo

### 1. Enkratna namestitev

```bash
./install-firefox-eid.sh
```

Skripta bo:

1. Dodala uporabnika v skupino `plugdev` — nato se **odjavi in ponovno prijavi**, da se pravice uveljavijo (ali izvedi `newgrp plugdev`)
2. Namestila manjkajoče pakete
3. Vprašala, naj avtomatski zagon `pcscd` ostane omogočen ali ga onemogoči:
   - odgovor **n** → pcscd se onemogoči in ustavi; v celoti ga upravlja `start-firefox-pcscd.sh` (priporočeno)
   - **Enter / y** → avtomatski zagon ostane, kot je trenutno nastavljen
4. Namestila Snap Firefox in ga povezala s pcscd
5. Pripravila Firefox profil za pametne kartice
6. Konfigurirala OpenSC (ohranjen je backup `opensc.conf` s časovnim žigom)

### 2. Zagon eID seje

```bash
./start-firefox-pcscd.sh [URL]
```

Skripta bo:

1. Preverila predpogoje (članstvo v skupini `plugdev`, Snap Firefox, snap povezavo s pcscd, potrebne pakete)
2. Zagnala `pcscd.service` + `pcscd.socket` in počakala na aktivno stanje (največ 10 s)
3. Preverila prisotnost bralnika in kartice prek `pcsc_scan` — po želji lahko nadaljuješ tudi brez njiju
4. Zagnala Firefox (po želji z podano URL). Če Firefox že teče, odpre nov zavihek in počaka, da zapreš **vsa** okna Firefoxa
5. Po zaprtju Firefoxa: počaka kratek čas za dokončanje operacij s kartico, ustavi `pcscd` (po potrebi s kill) in počisti komunikacijski socket

### 3. Hiter zagon z dvoklikom (Startup Service Card Reader)

Če želiš samo **zagnati** `pcscd`, brez celotne Firefox seje, uporabi zaganjalnik:

1. Dvokliki na `StartupServiceCardReader.desktop` v tej mapi.
   - Pri prvem zagonu (GNOME/Ubuntu): desni klik na datoteko → **Allow Launching** (Dovoli zagon) — dokler tega ne storiš, je označen kot "Untrusted launcher".
2. Odpre se terminalsko okno in zažene `startup-service-card-reader.sh`. Prikaže se **GUI okno za vnos gesla** (polkit) — vnesi geslo svojega računa, da dovoliš zagon servisa.
3. Skripta zagnane `pcscd.service` + `pcscd.socket`, izpiše rezultat in čaka na **Enter** za zaprtje. Če polkit agent ni na voljo, se uporabi navadno `sudo` vprašanje v terminalu.

Nasvet: desni klik → *Add to Desktop* (Dodaj na namizje) ali *Add to Favorites*, da bo vedno na dosegu roke. Za ugasnitev pcscd nato izvedi: `sudo systemctl stop pcscd.service pcscd.socket`.

### 4. Preverjanje nastavitve

```bash
pkcs11-tool -L        # naj izpiše samo visoko-varnostne eID sloti
pcsc_scan             # pokaže stanje bralnika/kartice
```

V Firefoxu: *Nastavitve → Zasebnost in varnost → Varnostne naprave* — naveden naj bo OpenSC modul in certifikati s tvoje kartice.

## Odpravljanje težav / ročni koraki

- **Bralnik ni zaznan** — preveri `lsusb`, poskusi drug USB priključek ali kabel; `pcsc_scan` zaženi, ko pcscd teče
- **OpenSC modul manjka v Firefoxu** — skripta `install-firefox-eid.sh` ga doda samodejno (v datoteko `pkcs11.txt` profila). Če ga vseeno ni, ga naloži ročno: *Nastavitve → Zasebnost in varnost → Varnostne naprave → Naloži* in vpiši `opensc-pkcs11.so`, nato Firefox ponovno zagnaj
- **Ponovna povezava snap vmesnika**: `sudo snap connect firefox:pcscd`
- **Ročno upravljanje pcscd**:

  ```bash
  sudo systemctl start pcscd.service pcscd.socket   # pred uporabo kartice
  sudo systemctl stop pcscd.service pcscd.socket    # po uporabi
  ```

- **Pregled OpenSC konfiguracije**: `/etc/opensc/opensc.conf` (backupi se hranijo kot `opensc.conf.bak.<časovni žig>`)

## Ročno nastavljanje

> **Opomba:** Večino nastavitev avtomatizira skripta `install-firefox-eid.sh`. Spodnja navodila so za referenco in ročne posege.

### 1. OpenSC konfiguracija (onemogoči nizko-varnostni certifikat)

Skripta to naredi samodejno. Za ročno urejanje:

```bash
sudo nano /etc/opensc/opensc.conf
```

in vneseš:

```
app default {
    framework pkcs15 {
        # Slovenski eID - nizka varnost (brez PIN-a, "Prijava brez PIN-a")
        application E828BD080F014E585031 {
            model = "ChipDocLite";
            disable = true;
            user_pin = "Norm PIN";
        }

        # Slovenski eID - visoka varnost (QES, "Podpis in prijava")
        application E828BD080F014E585030 {
            model = "ChipDocLite";
            user_pin = "Norm PIN";
            sign_pin = "Sig PIN";
        }
    }
}
```

To lahko tudi skrajšaš — gre samo za to, da onemogočiš aplikacijo `*31` (nizka varnost).

### 2. Preverjanje slotov kartice

```bash
pkcs11-tool -L
```

sedaj izpiše samo ta dva slot-a z večjo varnostjo.

### 3. Dodajanje PKCS#11 modula v Firefox

Firefox (NSS) PKCS#11 module dejansko naloži iz **baze modulov** profila — datoteke
`pkcs11.txt` v imeniku profila. Skripta `install-firefox-eid.sh` to naredi samodejno:
v `pkcs11.txt` **vseh** profilov doda vnos `library=opensc-pkcs11.so` (idempotentno —
če vnos že obstaja, ga ne doda dvakrat). Ker je modul znotraj snap Firefoxa, se uporabi
**golo ime** knjižnice (brez absolutne poti) — snap ga sam najde. To je isti mehanizem,
kot ga shrani dialog *Naloži*.

Če avtomatika ne deluje, modul naloži ročno:
- **Prek dialoga**: *Nastavitve → Zasebnost in varnost → Varnostne naprave → Naloži* in
  vpiši ime datoteke (brez poti) `opensc-pkcs11.so`, nato Firefox ponovno zagnaj.
- **Prek datoteke** `pkcs11.txt` profila (pot:
  `~/snap/firefox/common/.mozilla/firefox/<profil>/pkcs11.txt`) — dodaj:

  ```
  library=opensc-pkcs11.so
  name=OpenSC Smartcard Framework
  ```

  (modul se naloži ob naslednjem zagonu Firefoxa).

### 4. Snap Firefox — povezava s pcscd

Skripti to naredita samodejno. Za ročno:

```bash
sudo snap connect firefox:pcscd
```

### 5. Zagon Firefoxa za eID

Uporabi skripto, ki upravlja življenjski cikel pcscd:

```bash
./start-firefox-pcscd.sh
```

ali ročno:

```bash
sudo systemctl start pcscd.service pcscd.socket
snap run firefox
# ... po uporabi:
sudo systemctl stop pcscd.service pcscd.socket
```

> ⚠️ **POZOR:** Če je `pcscd` omogočen za avtomatski zagon in je kartica vstavljena ob bootu, jo OS lahko zahteva za prijavo namesto gesla! Priporočljivo je, da `pcscd` ostane onemogočen (disabled) in ga upravlja skripta `start-firefox-pcscd.sh`.

## Vir postopka

Postopek temelji na navodilih s foruma (avtor: SloTech), ki opisujejo, kako omogočiti uporabo slovenskih osebnih izkaznikov s čipom na Debian/Ubuntu sistemih. Ta projekt ta navodila samodejno pretvori v skripti.

## Datoteke

| Datoteka | Opis |
|---|---|
| `install-firefox-eid.sh` | Enkratna namestitvena skripta (zahteva sudo) |
| `start-firefox-pcscd.sh` | Skripta za upravljanje eID seje (zahteva sudo) |
| `StartupServiceCardReader.desktop` | Zaganjalnik za dvoklik — zagon pcscd (Ubuntu/Debian) |
| `startup-service-card-reader.sh` | Zažene `pcscd.service` + `pcscd.socket` z GUI (polkit) ali sudo avtentikacijo; uporablja ga zaganjalnik |
| `startup-service-card-reader-icon.png` | Ikona, ki jo uporablja zaganjalnik |

## Licenca

[MIT](LICENSE)
