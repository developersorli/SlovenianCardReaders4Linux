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
- Pripravi se Firefox profil za pametne kartice (samodejni izbor osebnega certifikata, brez začetnih varnostnih okenc)
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

### 3. Preverjanje nastavitve

```bash
pkcs11-tool -L        # naj izpiše samo visoko-varnostne eID sloti
pcsc_scan             # pokaže stanje bralnika/kartice
```

V Firefoxu: *Nastavitve → Zasebnost in varnost → Varnostne naprave* — naveden naj bo OpenSC modul in certifikati s tvoje kartice.

## Odpravljanje težav / ročni koraki

- **Bralnik ni zaznan** — preveri `lsusb`, poskusi drug USB priključek ali kabel; `pcsc_scan` zaženi, ko pcscd teče
- **OpenSC modul manjka v Firefoxu** — naloži ga ročno: *Nastavitve → Zasebnost in varnost → Varnostne naprave → Naloži* in vpiši ime datoteke modula (npr. `opensc-pkcs11.so`)
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

### 3. Ročno dodajanje PKCS#11 modula v Firefox (če avtomatika ne deluje)

V Firefoxu pojdi na: *Nastavitve → Zasebnost in varnost → Varnostne naprave*, dodaš z "Naloži":
- Ime datoteke (brez poti): `opensc-pkcs11.so`

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

## Licenca

[MIT](LICENSE)
