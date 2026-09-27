# SlovenianCardReaders4Linux

A pair of shell scripts that prepare an Ubuntu/Debian system to use the **Slovenian electronic identity (eID)** smart card with a USB card reader in **Firefox**. The same setup works with other PKCS#15 cards, such as the Spanish DNIe.

## What is this?

Using a smart card on Linux involves several moving parts:

- **pcscd** — the PC/SC daemon that talks to your USB card reader (via `libccid`)
- **OpenSC** — PKCS#11 middleware that exposes the certificates and PINs stored on the card to applications
- **Firefox (snap)** — a confined application that can only reach pcscd through an explicit snap interface connection

This project automates all of it:

| Script | Purpose |
|---|---|
| `install-firefox-eid.sh` | One-time system setup (packages, user groups, Snap Firefox, OpenSC configuration) |
| `start-firefox-pcscd.sh` | Runs a managed eID session: starts pcscd → launches Firefox → stops pcscd when you close it |

### Why manage pcscd manually?

If `pcscd` is enabled to start at boot and an eID card is inserted, the OS login manager can use the **card** for authentication instead of your password. To avoid that, this project keeps `pcscd` off by default and only starts it around a Firefox session — so the card is "live" only while you actually need it.

### What gets configured?

- Your user is added to the `plugdev` group (USB device access)
- Required packages are installed: `pcscd`, `libccid`, `libpcsclite1`, `pcsc-tools`, `opensc`, `snapd`
- Snap Firefox is installed and connected to pcscd (`sudo snap connect firefox:pcscd`)
- A Firefox profile is prepared for smart cards (OpenSC PKCS#11 module added to the profile's module database `pkcs11.txt`; optionally enable enterprise roots — trust system root certificates)
- OpenSC is configured so that only the **high-security** eID application (QES — "Podpis in prijava") is offered; the low-security pinless one ("Prijava brez PIN-a", AID `E828BD080F014E585031`) is disabled. The original `/etc/opensc/opensc.conf` is backed up before modification.

## Requirements

- Ubuntu or Debian (systemd + apt)
- Snap support (`snapd`)
- A CCID-compatible USB smart card reader (e.g., GEMPC 420, OmniKey CardMan 3121)
- A Slovenian eID card (or another PKCS#15 card such as DNIe)

## Usage

### 1. One-time installation

```bash
./install-firefox-eid.sh
```

The script will:

1. Add you to the `plugdev` group — **log out and back in** afterwards for it to take effect (or run `newgrp plugdev`)
2. Install any missing packages
3. Ask whether to keep or disable auto-start of `pcscd`:
   - answer **n** → pcscd is disabled/stopped and fully managed by `start-firefox-pcscd.sh` (recommended)
   - press **Enter / y** → pcscd keeps its current auto-start behaviour
4. Install Snap Firefox and connect it to pcscd
5. Prepare the Firefox profile for smart cards
6. Configure OpenSC (a timestamped backup of `opensc.conf` is kept)

### 2. Running an eID session

```bash
./start-firefox-pcscd.sh [URL]
```

The script will:

1. Verify prerequisites (`plugdev` membership, Snap Firefox, pcscd snap connection, required packages)
2. Start `pcscd.service` + `pcscd.socket` and wait until active (max 10 s)
3. Check that a reader (and card) is present via `pcsc_scan` — you can continue without one if you want
4. Launch Firefox (optionally with the URL you passed). If Firefox is already running, it opens a new tab and waits for **all** Firefox windows to be closed
5. After Firefox closes: wait briefly for card operations to finish, stop `pcscd` (escalating to kill if needed) and clean up its communication socket

### 3. Quick start with double-click (Startup Service Card Reader)

If you only want to **start** `pcscd` — without running the full Firefox session — use the launcher:

1. Double-click `StartupServiceCardReader.desktop` in this folder.
   - First run on GNOME/Ubuntu: right-click the file → **Allow Launching** (it is marked as an untrusted launcher until you do).
2. A terminal window opens and runs `startup-service-card-reader.sh`. A **GUI password dialog** (polkit) pops up — enter your user password there to authorize starting the service.
3. The script starts `pcscd.service` + `pcscd.socket`, shows the result, then waits for **Enter** to close. If no polkit agent is available it falls back to a normal `sudo` prompt in the terminal.

Tip: right-click → *Add to Desktop* (or *Add to Favorites*) to keep it one click away. To stop pcscd afterwards: `sudo systemctl stop pcscd.service pcscd.socket`.

### 4. Verifying the setup

```bash
pkcs11-tool -L        # should list only the high-security eID slots
pcsc_scan             # shows reader/card status
```

In Firefox: *Settings → Privacy & Security → Security Devices* — the OpenSC module and your card's certificates should be listed.

## Troubleshooting / manual steps

- **Reader not detected** — check `lsusb`, try another USB port/cable; run `pcsc_scan` while pcscd is running
- **OpenSC module missing in Firefox** — `install-firefox-eid.sh` adds it automatically (to the profile's `pkcs11.txt`). If it's still missing, load it manually: *Settings → Privacy & Security → Security Devices → Load* and enter `opensc-pkcs11.so`, then restart Firefox
- **Reconnect the snap interface**: `sudo snap connect firefox:pcscd`
- **Manual pcscd control**:

  ```bash
  sudo systemctl start pcscd.service pcscd.socket   # before using the card
  sudo systemctl stop pcscd.service pcscd.socket    # after
  ```

- **Inspect OpenSC configuration**: `/etc/opensc/opensc.conf` (backups are kept as `opensc.conf.bak.<timestamp>`)

For full manual setup instructions, see the *Ročno nastavljanje* section of [README_sl.md](README_sl.md).

## Files

| File | Description |
|---|---|
| `install-firefox-eid.sh` | One-time setup script (requires sudo) |
| `start-firefox-pcscd.sh` | Managed eID session runner (requires sudo) |
| `StartupServiceCardReader.desktop` | Double-clickable GUI launcher that starts pcscd (Ubuntu/Debian) |
| `startup-service-card-reader.sh` | Starts `pcscd.service` + `pcscd.socket` with GUI (polkit) or sudo auth; run by the launcher |
| `startup-service-card-reader-icon.png` | Icon used by the launcher |

## License

[MIT](LICENSE)
