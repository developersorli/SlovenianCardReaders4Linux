#!/bin/bash
# ==========================================================
# Startup Service Card Reader - zagon pcscd servisa (pcscd.service + pcscd.socket)
# Deluje na Ubuntu/Debian sistemih (systemd).
# Privilegije: pkexec/polkit (GUI okno za geslo), fallback na sudo.
# Uporablja ga zaganjalnik StartupServiceCardReader.desktop (dvoklik).
# ==========================================================

set -u

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}ℹ️  $*${NC}"; }
log_warn()  { echo -e "${YELLOW}⚠️  $*${NC}"; }
log_error() { echo -e "${RED}❌ $*${NC}" >&2; }

# Run a command as root: prefer pkexec (polkit -> GUI password dialog),
# fall back to plain sudo when no polkit agent is available.
# Returns: 0 = ok, 1 = failed, 2 = cancelled by user
run_privileged() {
    local err_file err rc
    err_file="$(mktemp)" || return 1
    pkexec "$@" 2>"$err_file"
    rc=$?
    if [[ $rc -eq 0 ]]; then
        rm -f "$err_file"
        return 0
    fi
    err="$(tr '\n' ' ' < "$err_file")"
    rm -f "$err_file"
    if [[ -z "${err// /}" || "$err" == *ancel* ]]; then
        log_warn "Avtentikacija preklicana — pcscd ni zagnan."
        return 2
    fi
    if [[ "$err" == *"authentication agent"* || "$err" == *NoReply* ]]; then
        log_warn "Polkit GUI agent ni na voljo — poskusim s sudo ..."
        if sudo "$@"; then return 0; else return 1; fi
    fi
    log_error "pkexec napaka: $err"
    return 1
}

echo ""
log_info "Startup Service Card Reader: zaganjam pcscd.service in pcscd.socket ..."
echo ""

if ! command -v systemctl &> /dev/null || ! systemctl cat pcscd.service &> /dev/null; then
    log_error "pcscd.service ni najden. Namesti ga z: sudo apt install pcscd"
    exit 1
fi

SYSTEMCTL_BIN="$(command -v systemctl)"

rc=0
if command -v pkexec &> /dev/null; then
    log_info "Odpre se GUI okno za vnos gesla (polkit) ..."
    run_privileged "$SYSTEMCTL_BIN" start pcscd.service pcscd.socket
    rc=$?
else
    log_info "Zahtevam pravice prek sudo ..."
    if ! sudo systemctl start pcscd.service pcscd.socket; then
        rc=1
    fi
fi

if [[ $rc -eq 2 ]]; then
    exit 0
elif [[ $rc -ne 0 ]]; then
    log_error "Zagon pcscd ni uspel. Preveri: sudo journalctl -u pcscd.service"
    exit 1
fi

sleep 1
if systemctl is-active --quiet pcscd.service; then
    log_info "✅ pcscd.service je aktiven."
else
    log_warn "pcscd.service se ni aktiviral. Preveri: sudo journalctl -u pcscd.service"
fi

echo ""
systemctl status pcscd.service --no-pager || true

