#!/usr/bin/env bash
# System-level hardening shared by the other setup steps: makes sure
# firewalld (not raw iptables/ip6tables) is what's managing the firewall,
# and disables IPv6 so firewalld stops trying to manage ip6tables rules
# for a stack nothing on this box actually uses.

ensure_firewalld() {
    if ! command -v firewall-cmd >/dev/null 2>&1; then
        log_info "Installing firewalld..."
        pkg_install firewalld >/dev/null
    fi
    systemctl enable --now firewalld >/dev/null 2>&1
    log_info "firewalld is running."
}

disable_ipv6() {
    log_info "Disabling IPv6..."

    cat > /etc/sysctl.d/99-autoproxy-disable-ipv6.conf <<'EOF'
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF
    sysctl -p /etc/sysctl.d/99-autoproxy-disable-ipv6.conf >/dev/null 2>&1 || true

    # Persist across reboots (module never loads) via the kernel cmdline.
    if command -v grubby >/dev/null 2>&1; then
        grubby --update-kernel=ALL --args="ipv6.disable=1" >/dev/null 2>&1 || true
    fi

    # With the IPv6 stack gone, firewalld's ip6tables rule-application
    # (rp_filter) has nothing to talk to and logs constant errors unless
    # told to stop trying.
    if [ -f /etc/firewalld/firewalld.conf ]; then
        if grep -q '^IPv6_rpfilter=' /etc/firewalld/firewalld.conf; then
            sed -i 's/^IPv6_rpfilter=.*/IPv6_rpfilter=no/' /etc/firewalld/firewalld.conf
        else
            echo 'IPv6_rpfilter=no' >> /etc/firewalld/firewalld.conf
        fi
        systemctl restart firewalld >/dev/null 2>&1 || true
    fi

    log_info "IPv6 disabled (active immediately via sysctl; kernel-level via grubby needs a reboot)."
}
