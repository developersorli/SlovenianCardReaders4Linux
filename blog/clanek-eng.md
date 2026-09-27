---
title: "How to Use Your Slovenian eID Card on Ubuntu — in 5 Minutes"
date: 2026-09-21
author: developersorli
tags: [linux, ubuntu, eid, smartcard, open-source]
description: "This open-source project finally enables Slovenian e-identity usage in Firefox on Linux — without Windows."
---

# How to Use Your Slovenian eID Card on Ubuntu — in 5 Minutes

## The backstory

Last year I ran into a problem that many Linux users in Slovenia will recognize: I needed a digital certificate to sign a document, but the only way to use it was — Windows. I had Ubuntu installed and wanted to access e-government services, electronically sign contracts, and log into e-health systems with my e-identity. The solution? **A dual-boot system**.

Later, I discovered [SlovenianCardReaders4Linux](https://github.com/developersorli/SlovenianCardReaders4Linux) — an open-source tool that automates everything needed to use a Slovenian eID card in Firefox on Linux. And now I wanted to share this story.

---

## What does the Slovenian e-identity enable?

The Slovenian electronic identity (eID) card is more than just a login password — it's a powerful tool for digital services:

| Service | Description |
|---|---|
| **e-Government** | Login to e-uprava.si portal, submit applications, view data |
| **e-Health** | Access personal health portal, prescriptions, referrals |
| **Electronic Signature** | Qualified e-signing of documents (QES) — legally valid |
| **Online Banking** | Login to some banks with a qualified certificate |

---

## How the project works

Using a smart card on Linux involves several components that must work together correctly:

- **USB card reader** — physical device for reading the card
- **pcscd daemon** — system service for communication with the reader
- **OpenSC PKCS#11** — software layer that exposes certificates and PIN on the card
- **Snap Firefox** — browser with interfaces to system resources
- **Firefox eID plugin** — extension for smart cards

The project automates connecting all these components.

---

## Installation — a safe step-by-step guide
> ⚠️ **Security warning:** Before running any script from the internet, always review its contents to make sure it doesn't do anything unexpected.

### Step 1: Download the script

```bash
wget https://github.com/developersorli/SlovenianCardReaders4Linux/raw/main/install-firefox-eid.sh
```

### Step 2: Review what it does (do not run yet!)

```bash
cat install-firefox-eid.sh
```

Read the contents and make sure you understand every step.

### Step 3: Run

```bash
chmod +x install-firefox-eid.sh
./install-firefox-eid.sh
```

Or a one-liner — but only after reviewing the script:

```bash
curl -sSL https://raw.githubusercontent.com/developersorli/SlovenianCardReaders4Linux/main/install-firefox-eid.sh | bash
```

---

## What does the installation script do?

The `install-firefox-eid.sh` script sets up the entire system:

| Step | What happens |
|---|---|
| 1. | Adding user to the `plugdev` group (USB device access) |
| 2. | Installing packages: `pcscd`, `libccid`, `libpcsclite1`, `pcsc-tools`, `opensc`, `snapd` |
| 3. | Disabling automatic pcscd startup (card cannot be abused for system login) |
| 4. | Installing Snap Firefox and connecting it to the pcscd service |
| 5. | Preparing Firefox profile for smart cards |
| 6. | Configuring OpenSC — only high-security eID application (QES) |

### Saving to desktop

The repository contains `StartupServiceCardReader.desktop`. Copy it to your `$HOME/.local/share/applications/` and you can double-click to launch the pcscd service without opening a browser — useful if you just need to check card data.

---

## Usage

After installation, an e-identity session is just one command:

```bash
./start-firefox-pcscd.sh [URL]
```

The script:
1. Starts the `pcscd` service
2. Opens Firefox (with the provided URL if given)
3. Stops `pcscd` after closing the browser

So the card is only "active" when you actually need it.

---

## Supported readers and cards

- **Readers:** any CCID-compatible USB reader (GEMPC 420, OmniKey CardMan 3121 …)
- **Cards:** Slovenian eID card or other PKCS#15 cards (e.g. Spanish DNIe)

---

## FAQ

**Does it work on Fedora / Arch / Manjaro?**
Currently only Ubuntu and Debian are supported (`systemd` + `apt`). Contributions for other distributions welcome!

**Does it work in Chrome or Chromium?**
No. The project currently works only with Firefox via the Snap interface.

**Why is automatic pcscd startup disabled?**

Without this, if a card is inserted when the system boots, `pcscd` would grab access to it — and the user wouldn't be able to enter their login password because the screen is "locked" waiting for the smart card. Even if you didn't want to use the card for system login (only for e-signing later), normal login would be blocked.

With auto-start disabled, you must explicitly start `pcscd` — meaning you're always in control of card access. At that point you know you'll need it for your e-identity.

**Do I need internet every time I use the card?**
No. The installation is one-time. The card and certificates are stored on it — you only need the internet for accessing web services.

---

## Conclusion

With the SlovenianCardReaders4Linux project, Linux users finally have full functionality of the Slovenian e-identity available to them. This is an excellent example of a community solving everyday problems and bringing open-source systems to wider use.

💡 Like this project? Support it with ⭐ on GitHub or contribute!

🔗 [Slovene version of the article](./clanek-slo.md)

**More information:** [GitHub repository](https://github.com/developersorli/SlovenianCardReaders4Linux)