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

ensure_swap() {
    if swapon --show --noheadings 2>/dev/null | grep -q .; then
        log_info "Swap already configured, skipping."
        return
    fi

    local total_mem_mb
    total_mem_mb=$(($(awk '/MemTotal/ {print $2}' /proc/meminfo) / 1024))

    if [ "$total_mem_mb" -ge 2048 ]; then
        log_info "RAM is ${total_mem_mb}MB and no swap is configured — should be enough headroom, skipping swap."
        return
    fi

    # `dnf update -y` alone regularly hits 600-700MB RSS on a full system
    # update; on the common 512MB-1GB VPS tier with no swap, that's an
    # instant OOM kill (seen in the wild: dnf killed on a 929MB box).
    # docker build later can spike too. A swap file is cheap, reversible
    # insurance against both.
    local swap_mb=2048
    log_warn "Low RAM (${total_mem_mb}MB) with no swap — dnf/docker build can get OOM-killed on small VPS instances. Creating a ${swap_mb}MB swap file at /swapfile..."

    fallocate -l "${swap_mb}M" /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count="$swap_mb" status=none
    chmod 600 /swapfile
    mkswap /swapfile >/dev/null
    swapon /swapfile

    if ! grep -q '^/swapfile ' /etc/fstab; then
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
    fi

    log_info "Swap enabled: $(swapon --show --noheadings | awk '{print $3}')."
}

system_update() {
    log_info "Updating system packages (this can take a few minutes)..."

    # Rocky/RHEL 9's legacy network-scripts package pins an old
    # initscripts version and blocks `dnf update` outright. The tempting
    # fix is --allowerasing, but that gives dnf free rein to erase *any*
    # conflicting package to resolve the transaction — on at least one
    # box it chose to erase NetworkManager instead, which took the
    # network interface down (and with it, SSH). So: remove the actual
    # offending package by name, only when it's safe to (NetworkManager
    # is the one actually running the network already), and never hand
    # dnf a blank cheque to erase things on our behalf.
    if [ "$PKG_MGR" = "dnf" ] && rpm -q network-scripts >/dev/null 2>&1; then
        if systemctl is-active --quiet NetworkManager; then
            log_info "Removing legacy network-scripts (NetworkManager is running the network)..."
            dnf remove -y network-scripts >/dev/null
        else
            log_warn "network-scripts is installed and NetworkManager is not active — leaving it in place (networking may depend on it). initscripts may not fully update."
        fi
    fi

    # openssh* is intentionally excluded: dnf update triggers a full sshd
    # restart (systemctl try-restart), which would drop the very SSH
    # session this script is usually piped in over, killing the script
    # mid-run. Update openssh separately, deliberately, from a console.
    # NetworkManager* is excluded too, as a second line of defense: it
    # must never be a candidate for removal by this step.
    "$PKG_MGR" update -y --exclude='openssh*' --exclude='NetworkManager*' >/dev/null
    log_info "System packages updated (openssh excluded — see README)."
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
