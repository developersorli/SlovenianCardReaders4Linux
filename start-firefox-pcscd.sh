#!/bin/bash

set -euo pipefail 2>/dev/null || set -eu

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()   { echo -e "${GREEN}ℹ️  $*${NC}"; }
log_warn()   { echo -e "${YELLOW}⚠️  $*${NC}"; }
log_error()  { echo -e "${RED}❌ $*${NC}" >&2; }

# ==========================================
# 1. Preveri članstvo v 'plugdev'
# ==========================================
if ! groups "$(whoami)" | grep -q plugdev; then
    log_warn "Uporabnik '$(whoami)' ni v skupini 'plugdev'."
    read -p "Dodam te v skupino 'plugdev'? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        sudo usermod -aG plugdev "$(whoami)"
        log_info "Znova se prijavi ali uporabi: newgrp plugdev"
        log_warn "Skripta se bo nadaljevala, vendar lahko pride do težav z dostopom do čitača."
        log_info "Priporočam, da se odjaviš in ponovno prijaviš, preden zaženeš skripto ponovno."
    else
        log_error "Brez dostopa do USB čitačev ne morem nadaljevati."
        exit 1
    fi
fi

# ==========================================
# 2. Preveri Snap Firefox
# ==========================================
if ! command -v snap &> /dev/null; then
    log_error "Snap ni nameščen. Namesti ga z: sudo apt install snapd"
    exit 1
fi

if ! snap list firefox &> /dev/null; then
    log_error "Snap Firefox ni nameščen."
    log_info "Zaženi install-firefox-eid.sh za namestitev, ali namesti ročno:"
    log_info "  sudo snap install firefox"
    exit 1
fi

log_info "✅ Snap Firefox je nameščen."

FIREFOX_CMD="snap run firefox"
FIREFOX_NAME="Firefox (Snap)"

# ==========================================
# 3. Preveri snap connect firefox:pcscd
# ==========================================
log_info "Preverjam povezavo firefox:pcscd..."
if snap connections firefox 2>/dev/null | grep -q ":pcscd"; then
    log_info "✅ Firefox je povezan s pcscd."
else
    log_warn "Firefox ni povezan s pcscd."
    read -p "Povežem Firefox s pcscd? (Y/n) " -n 1 -r
    echo
    if [[ -z "$REPLY" ]] || [[ $REPLY =~ ^[Yy]$ ]]; then
        sudo snap connect firefox:pcscd
        log_info "✅ Firefox povezan s pcscd."
    else
        log_error "Brez povezave s pcscd Firefox ne bo zaznal čitalca kartic."
        exit 1
    fi
fi

# ==========================================
# 4. Preveri in namesti sistemske pakete (pcscd, libccid, libpcsclite1)
# ==========================================
PACKAGES_NEEDED=("pcscd" "libccid" "libpcsclite1")

MISSING=()
for pkg in "${PACKAGES_NEEDED[@]}"; do
    if ! dpkg -l "$pkg" &> /dev/null; then
        MISSING+=("$pkg")
    fi
done

if [[ ${#MISSING[@]} -gt 0 ]]; then
    log_warn "Manjkajo: ${MISSING[*]}"
    read -p "Namestim manjkajoče? (y/N) " -n 1 -r; echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        sudo apt update -qq && sudo apt install -y "${MISSING[@]}"
    else
        log_error "Potreben paket manjka."
        exit 1
    fi
fi

# ==========================================
# 5. Zagon pcscd (servis)
# ==========================================
if ! systemctl cat pcscd.service &> /dev/null; then
    log_error "pcscd.service ni najden. Namesti: sudo apt install pcscd"
    exit 1
fi

log_info "Zaganjam pcscd.service in pcscd.socket..."
sudo systemctl start pcscd.service pcscd.socket

# Počakaj, da se zagne (max 10s)
log_info "Čakam na aktivno stanje pcscd.service..."
if ! timeout 10 bash -c 'until systemctl is-active --quiet pcscd.service; do sleep 0.25; done'; then
    log_warn "pcscd se ne zazna v 10 sekundah."
    log_info "Poišči napake: sudo journalctl -u pcscd.service"
fi

# ==========================================
# 6. Preveri čitač
# ==========================================
if command -v pcsc_scan &> /dev/null; then
    log_info "Preverjam prisotnost čitača in kartice..."
    
    timeout 8 pcsc_scan > /tmp/pcsc.out 2>&1 || true
    
    if grep -qi "card inserted" /tmp/pcsc.out; then
        log_info "✅ Smart-kartica zaznana: $(grep -i 'card inserted' /tmp/pcsc.out | head -n1)"
    elif grep -qi "waiting for a reader to be inserted" /tmp/pcsc.out; then
        log_warn "⚠️  Čitač ni priključen ali ni zaznan."
        read -p "Želiš nadaljevati kljub temu? (y/N) " -n 1 -r; echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            rm -f /tmp/pcsc.out
            exit 1
        fi
    elif grep -qi "no card" /tmp/pcsc.out; then
        log_warn "⚠️  Čitač deluje, vendar ni vstavljene kartice."
        read -p "Želiš nadaljevati kljub temu? (y/N) " -n 1 -r; echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            rm -f /tmp/pcsc.out
            exit 1
        fi
    else
        log_warn "⚠️  Preverjanje čitača ni uspelo. Ali je čitač priključen?"
        read -p "Želiš nadaljevati kljub temu? (y/N) " -n 1 -r; echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            rm -f /tmp/pcsc.out
            exit 1
        fi
    fi
    
    rm -f /tmp/pcsc.out
fi

# ==========================================
# 7. Zagon Firefox-a
# ==========================================
log_info "➡️  Odpiram $FIREFOX_NAME..."

# Funkcija za preverjanje ali Firefox ima odprta okna
firefox_has_windows() {
    if command -v xdotool &> /dev/null; then
        # Uporabimo xdotool za preverjanje oken
        local windows=$(xdotool search --class "Firefox" 2>/dev/null | wc -l)
        [ "$windows" -gt 0 ]
    else
        # Fallback: preverimo procese, vendar izključimo trenutni PID in morebitne podprocese
        local current_pid=$$
        local firefox_pids=$(pgrep -f "firefox" 2>/dev/null || true)
        
        # Preverimo vsak PID
        for pid in $firefox_pids; do
            # Če je PID enak trenutnemu procesu ali njegovemu staršu, preskoči
            if [ "$pid" != "$current_pid" ] && [ "$(ps -o ppid= -p $pid 2>/dev/null | tr -d ' ')" != "$current_pid" ]; then
                # Preverimo še ali je to dejanski Firefox proces (ne skripta)
                local cmdline=$(ps -o cmd= -p $pid 2>/dev/null || true)
                if [[ "$cmdline" == *"firefox"* ]] && [[ "$cmdline" != *"bash"* ]] && [[ "$cmdline" != *"sh"* ]]; then
                    return 0
                fi
            fi
        done
        return 1
    fi
}

# Preverimo ali Firefox že teče in ima okna
if firefox_has_windows; then
    log_warn "Firefox že teče z odprtimi okni."
    read -p "Želiš odpreti nov zavihek in počakati, da zapreš VSE Firefox okna? (y/N) " -n 1 -r; echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        # Odpremo nov zavihek v obstoječi instanci
        $FIREFOX_CMD --new-tab "$@" &
        
        log_info "Čakam, da zapreš VSA Firefox okna..."
        log_info "Ko zapreš zadnje Firefox okno, se bo skripta nadaljevala."
        
        # Počakamo, da ni več odprtih Firefox oken
        while firefox_has_windows; do
            sleep 2
            echo -n "."
        done
        echo ""
        
        log_info "Vsa Firefox okna so zaprta."
        
        # Počakamo še malo, da se procesi dokončno zaključijo
        sleep 2
    else
        log_warn "Nadaljujem brez čakanja na zaprtje Firefoxa."
        log_error "pcscd bo zaustavljen takoj, kar lahko povzroči težave s kartico!"
        read -p "Vseeno nadaljuj? (y/N) " -n 1 -r; echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
else
    # Firefox ne teče ali nima oken, zaženemo ga in počakamo na zaprtje
    log_info "Zaganjam $FIREFOX_NAME in čakam na zaprtje..."
    $FIREFOX_CMD "$@"
    log_info "Firefox je zaprt."
fi

# ==========================================
# 8. Ko se Firefox zapre — zaustavi pcscd
# ==========================================
echo ""
log_info "Nadaljujem z zaustavljanjem pcscd..."

# Počakamo, da se morebitne operacije s kartico zaključijo
log_info "Čakam 3 sekunde, da se operacije s kartico zaključijo..."
sleep 3

log_info "Preverjam stanje pcscd.service..."
if systemctl is-active --quiet pcscd.service; then
    log_warn "pcscd.service je še vedno aktiven. Ugasnjam..."
    
    # Poskusimo najprej nežno ustaviti
    sudo systemctl stop pcscd.service pcscd.socket 2>/dev/null || true
    
    # Počakamo malo in preverimo
    sleep 2
    
    # Če je še vedno aktiven, poskusimo z močnejšim načinom
    if systemctl is-active --quiet pcscd.service; then
        log_warn "pcscd.service se ne ustavi normalno. Poskušam s kill..."
        sudo systemctl kill pcscd.service 2>/dev/null || true
        sleep 1
    fi
    
    # Končno preverjanje
    if systemctl is-active --quiet pcscd.service; then
        log_error "❌ pcscd.service se ne ugasne – preveri z: sudo journalctl -u pcscd.service"
        log_warn "Lahko poskusiš ročno: sudo systemctl stop pcscd.service"
    else
        log_info "✅ pcscd.service uspešno zaustavljen."
    fi
else
    log_info "pcscd.service je že ugasnjen."
fi

# Počistimo komunikacijski socket (če obstaja)
if [ -e /run/pcscd/pcscd.comm ]; then
    sudo rm -f /run/pcscd/pcscd.comm 2>/dev/null || true
    log_info "Počiščen komunikacijski socket."
fi

log_info "✅ Končano: vse čisto."