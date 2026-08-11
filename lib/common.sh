#!/usr/bin/env bash
# Shared helpers for autoproxy install scripts.

log_info() { echo -e "\033[1;34m[autoproxy]\033[0m $*"; }
log_warn() { echo -e "\033[1;33m[autoproxy][warn]\033[0m $*"; }
log_err()  { echo -e "\033[1;31m[autoproxy][error]\033[0m $*" >&2; }

require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        log_err "This script must be run as root (use sudo)."
        exit 1
    fi
}

detect_pkg_mgr() {
    if command -v dnf >/dev/null 2>&1; then
        echo "dnf"
    elif command -v yum >/dev/null 2>&1; then
        echo "yum"
    else
        log_err "No supported package manager found (dnf/yum). This installer targets CentOS/Rocky Linux/RHEL."
        exit 1
    fi
}

pkg_install() {
    "$PKG_MGR" install -y "$@"
}

random_password() {
    tr -dc 'A-Za-z0-9' < /dev/urandom | head -c "${1:-20}"
}

firewalld_open_port() {
    local port="$1" proto="${2:-tcp}"
    if command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active --quiet firewalld; then
        firewall-cmd --permanent --add-port="${port}/${proto}" >/dev/null
        firewall-cmd --reload >/dev/null
        log_info "Opened ${port}/${proto} in firewalld."
    fi
}

export PKG_MGR
PKG_MGR="$(detect_pkg_mgr)"
