#!/bin/bash

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()   { echo -e "${GREEN}✔️  $*${NC}"; }
log_warn()   { echo -e "${YELLOW}⚠️  $*${NC}"; }
log_error()  { echo -e "${RED}❌ $*${NC}" >&2; }

# ==========================================
# 0. Preveri pravice (root ni potreben, ampak sudo)
# ==========================================
if [[ $EUID -ne 0 ]]; then
    log_warn "Skripta bo zahtevala 'sudo'. Pridobivam pravice..."
fi

echo ""
log_info "🛠️  Nameščanje in priprava okolja za slovensko elektronsko identifikacijo (eID)"
echo ""

# ==========================================
# 1. Dodaj uporabnika v skupino 'plugdev'
# ==========================================
USER=$(whoami)
if ! groups "$USER" | grep -q plugdev; then
    log_info "Dodajam '$USER' v skupino 'plugdev' (dostop do USB naprav)..."
    sudo usermod -aG plugdev "$USER"
    log_info "✅ Dodan. Znova se prijavi ali uporabi 'newgrp plugdev', da se pravice uveljavijo."
else
    log_info "Uporabnik '$USER' že pripada skupini 'plugdev'."
fi

# ==========================================
# 2. Namesti potrebne pakete (Ubuntu/Debian)
# ==========================================
PACKAGES=(
    "pcscd"
    "libccid"
    "libpcsclite1"
    "pcsc-tools"           # za pcsc_scan
    "opensc"               # za pkcs15-tool, uporabno za preverjanje kartic
    "snapd"                # za snap Firefox
)

log_info "Preverjam in nameščam pakete..."
sudo apt update -qq || { log_error "Apt update ni uspel!"; exit 1; }

MISSING=()
for pkg in "${PACKAGES[@]}"; do
    if ! dpkg -l "$pkg" &> /dev/null; then
        MISSING+=("$pkg")
    fi
done

if [[ ${#MISSING[@]} -gt 0 ]]; then
    log_info "Nameščam: ${MISSING[*]}"
    sudo apt install -y "${MISSING[@]}" || { log_error "Napaka pri namestitvi paketov!"; exit 1; }
else
    log_info "Vsi potrebni paketi že nameščeni."
fi

# ==========================================
# 3. pcscd - upravljanje avtomatskega zagona
# ==========================================
if systemctl cat pcscd.service &> /dev/null; then
    if systemctl is-enabled pcscd.service &> /dev/null; then
        echo ""
        log_warn "pcscd.service je OMOGOČEN za avtomatski zagon ob zagonu sistema."
        log_warn "Če je kartica vstavljena ob bootu, jo OS lahko zahteva za prijavo namesto gesla!"
        echo ""
        read -p "$(echo -e ${YELLOW}Želiš omogočiti avtomatski zagon pcscd? ${NC}[Y/n]) " -n 1 -r
        echo
        if [[ -z "$REPLY" ]] || [[ $REPLY =~ ^[Yy]$ ]]; then
            log_warn "pcscd.service ostaja omogočen. Po potrebi ga lahko kasneje onemogočiš z:"
            log_warn "  sudo systemctl disable pcscd.service"
        else
            sudo systemctl disable pcscd.service
            sudo systemctl stop pcscd.service pcscd.socket 2>/dev/null || true
            log_info "pcscd.service onemogočen in ustavljen. Upravljala ga bo skripta start-firefox-pcscd.sh."
        fi
    else
        log_info "✅ pcscd.service ni omogočen za avtomatski zagon – v redu."
    fi
else
    log_warn "pcscd.service ni najden – preveri: ali je paket 'pcscd' nameščen?"
    log_warn "Namesti ga z: sudo apt install pcscd"
fi

# ==========================================
# 4. Snap Firefox - preveri in namesti
# ==========================================
log_info "Preverjam Snap Firefox..."

if ! command -v snap &> /dev/null; then
    log_error "Snap ni nameščen. Namesti snapd: sudo apt install snapd"
    exit 1
fi

if snap list firefox &> /dev/null; then
    log_info "✅ Snap Firefox je že nameščen."
else
    log_info "Nameščam Firefox prek Snap-a..."
    sudo snap install firefox || {
        log_error "Snap Firefox namestitev ni uspela. Preveri snapd delovanje."
        exit 1
    }
    log_info "✅ Snap Firefox nameščen."
fi

# ==========================================
# 5. snap connect firefox:pcscd
# ==========================================
log_info "Povezujem Firefox s pcscd (snap connect)..."
sudo snap connect firefox:pcscd 2>/dev/null || {
    log_warn "snap connect firefox:pcscd ni uspel. Poskusi ročno:"
    log_warn "  sudo snap connect firefox:pcscd"
}
log_info "✅ Firefox povezan s pcscd."

# ==========================================
# 6. Preveri čitače in priporočila za eID
# ==========================================
log_info "Preverjam podprte čitače..."
echo ""
if command -v pcsc_scan &> /dev/null; then
    if timeout 8 pcsc_scan > /tmp/pcsc_list.txt 2>&1 || true; then
        grep -E 'Reader|Card' /tmp/pcsc_list.txt 2>/dev/null || log_warn "Ni zaznanih čitačev. Priključi čitač in ponovi test."
    fi
    rm -f /tmp/pcsc_list.txt
fi

# ==========================================
# 7. Ustvari/nastavi Firefox profil za eID (Snap pot)
# ==========================================
SNAP_FIREFOX_DIR="$HOME/snap/firefox/common/.mozilla/firefox"

if [[ -d "$SNAP_FIREFOX_DIR" ]]; then
    default_ini="$SNAP_FIREFOX_DIR/profiles.ini"
    FIREFOX_PROFILE_DIR=""

    if [[ -f "$default_ini" ]]; then
        profile_path=$(grep "Path=" "$default_ini" | head -n1 | cut -d= -f2-)
        if [[ -n "$profile_path" ]]; then
            FIREFOX_PROFILE_DIR="$SNAP_FIREFOX_DIR/$profile_path"
        fi
    fi

    if [[ -z "$FIREFOX_PROFILE_DIR" ]] || [[ ! -d "$FIREFOX_PROFILE_DIR" ]]; then
        log_info "Ustvarjam nov Firefox profil za eID..."
        timeout 15 bash -c 'export DISPLAY=:0 && snap run firefox -CreateProfile eid-profile' 2>/dev/null || {
            log_warn "Ne morem samodejno ustvariti profila (potrebuješ X sejo)."
            log_warn "Ročno zaženi: snap run firefox -p"
        }
        # Preveri, če je bil ustvarjen
        profile_line=$(grep "Path=eid-profile" "$default_ini" 2>/dev/null || true)
        if [[ -n "$profile_line" ]]; then
            FIREFOX_PROFILE_DIR="$SNAP_FIREFOX_DIR/eid-profile"
        fi
    fi

    if [[ -d "$FIREFOX_PROFILE_DIR" ]]; then
        log_info "Nastavljam Firefox profil '$FIREFOX_PROFILE_DIR' za eID..."

        cat > "$FIREFOX_PROFILE_DIR/user.js" <<'EOF'
// Samodejna podpora za pkcs#11 (potrebno za DNIe/GEMPC čitače)
user_pref("security.smartcard_db", "true");
user_pref("security.disable_initial_dialogs", true);
user_pref("browser.sessionstore.resume_from_crash", false);

// Prepreči predlogo "vprašaj pri vsaki uporabi" – uporabnik določi
user_pref("security.default_personal_cert", "Select Automatically");

// Omogoči enterprise roots za sistemsko PKCS#11
user_pref("security.enterprise_roots.enabled", true);

// Dodaj OpenSC PKCS#11 modul (narejen ročno prek Varnostnih Naprav, če ne deluje samodejno)
// Pot: /usr/lib/x86_64-linux-gnu/opensc-pkcs11.so
EOF

        log_info "✅ Firefox profil pripravljen."
    else
        log_warn "Ne morem najti/ustvariti profila. Ročno poženi: snap run firefox -p"
    fi
else
    log_warn "Snap Firefox profilna mapa ($SNAP_FIREFOX_DIR) še ne obstaja."
    log_warn "Zaženi Firefox vsaj enkrat, da ustvari profil, nato ponovno poženi to skripto."
fi

# ==========================================
# 8. OpenSC konfiguracija - onemogoči nizko-varnostni certifikat
# ==========================================
OPENSC_CONF="/etc/opensc/opensc.conf"

log_info "Preverjam OpenSC konfiguracijo..."

if [[ -f "$OPENSC_CONF" ]]; then
    if grep -q "E828BD080F014E585031" "$OPENSC_CONF" 2>/dev/null; then
        log_info "✅ OpenSC konfiguracija za eID že vsebuje nastavitve."
    else
        log_info "Dodajam eID nastavitve v $OPENSC_CONF..."
        echo ""
        log_warn "Dodal bom blokado nizko-varnostnega certifikata (Prijava brez PIN-a)."
        log_warn "Visoko-varnostni certifikat (Podpis in prijava) ostane omogočen."
        echo ""
        read -p "$(echo -e ${YELLOW}Želiš dodati OpenSC eID konfiguracijo? ${NC}[Y/n]) " -n 1 -r
        echo
        if [[ -z "$REPLY" ]] || [[ $REPLY =~ ^[Yy]$ ]]; then
            # Backup originalne konfiguracije
            sudo cp "$OPENSC_CONF" "$OPENSC_CONF.bak.$(date +%Y%m%d_%H%M%S)"

            # Dodaj konfiguracijo (pred zaključkom datoteke, če je app default že definiran,
            # sicer dodaj celoten blok)
            if grep -q "^app default" "$OPENSC_CONF" 2>/dev/null; then
                # app default že obstaja - dodaj framework pkcs15 znotraj, če še ni
                if ! grep -q "framework pkcs15" "$OPENSC_CONF" 2>/dev/null; then
                    log_info "app default obstaja, vstavljam framework pkcs15 blok..."
                    sudo sed -i '/^app default {/,/^}/ {
                        /^}/ {
                            i\
    framework pkcs15 {\
        application E828BD080F014E585031 {\
            model = "ChipDocLite";\
            disable = true;\
            user_pin = "Norm PIN";\
        }\
\
        application E828BD080F014E585030 {\
            model = "ChipDocLite";\
            user_pin = "Norm PIN";\
            sign_pin = "Sig PIN";\
        }\
    }
                        }
                    }' "$OPENSC_CONF"
                    log_info "✅ Framework pkcs15 dodan v app default."
                else
                    log_info "✅ Framework pkcs15 že obstaja v app default."
                fi
            else
                # Dodaj celoten app default blok
                sudo tee -a "$OPENSC_CONF" > /dev/null <<'OPENSC_EOF'

app default {
    framework pkcs15 {
        # Slovenian eID - low level (pinless, "Prijava brez PIN-a")
        application E828BD080F014E585031 {
            model = "ChipDocLite";
            disable = true;
            user_pin = "Norm PIN";
        }

        # Slovenian eID - high level (QES, "Podpis in prijava")
        application E828BD080F014E585030 {
            model = "ChipDocLite";
            user_pin = "Norm PIN";
            sign_pin = "Sig PIN";
        }
    }
}
OPENSC_EOF
                log_info "✅ OpenSC eID konfiguracija dodana."
            fi
        else
            log_warn "OpenSC konfiguracija preskočena. Po potrebi jo uredi ročno v $OPENSC_CONF."
        fi
    fi
else
    log_warn "$OPENSC_CONF ne obstaja. Se bo ustvaril, ko se prvič uporabi OpenSC."
    log_info "Po potrebi ga ustvari z: sudo nano $OPENSC_CONF"
fi

# ==========================================
# 9. Pripomni uporabnika o potrebah
# ==========================================
echo ""
log_info "📋 Naslednji koraki:"
echo "   • Priključi čitač (npr. GEMPC 420, OmniKey CardMan 3121)"
echo "   • Vstavi elektronsko identiteto ali kartico DNIe"
echo "   • Poženi: ./start-firefox-pcscd.sh"
echo ""
log_info "🚀 Vse pripravljeno. Znova se prijavi za uveljavitev 'plugdev' članstva!"