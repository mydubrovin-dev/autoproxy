#!/usr/bin/env bash
# Installs and configures fail2ban to protect SSH from brute-force attempts.

# Never banned, regardless of failed attempts. Override/extend with
# AUTOPROXY_TRUSTED_IPS (space-separated IPs/CIDRs), e.g.:
#   AUTOPROXY_TRUSTED_IPS="203.0.113.5 198.51.100.0/24" curl ... | sudo bash
DEFAULT_TRUSTED_IPS="127.0.0.1/8 ::1 81.211.68.176/28 212.24.52.192/28 217.22.164.0/28 77.51.177.18/32"

setup_fail2ban() {
    log_info "Installing fail2ban..."

    if [ "$PKG_MGR" = "dnf" ] && ! rpm -q epel-release >/dev/null 2>&1; then
        pkg_install epel-release >/dev/null 2>&1 || true
    fi
    # ipset is required by the firewallcmd-ipset ban action below.
    pkg_install fail2ban firewalld ipset >/dev/null

    local logpath="/var/log/secure"
    [ -f /var/log/auth.log ] && logpath="/var/log/auth.log"

    local ignoreip="$DEFAULT_TRUSTED_IPS"
    if [ -n "${AUTOPROXY_TRUSTED_IPS:-}" ]; then
        ignoreip="$ignoreip $AUTOPROXY_TRUSTED_IPS"
    fi

    # Ban via firewalld (ipset + rich rules) instead of fail2ban's default
    # raw iptables/ip6tables actions, which fight with firewalld for
    # control of the same tables on Rocky/RHEL.
    cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
bantime  = 1h
findtime = 10m
maxretry = 5
backend  = systemd
ignoreip = ${ignoreip}
banaction = firewallcmd-ipset
banaction_allports = firewallcmd-allports

[sshd]
enabled  = true
port     = ssh
filter   = sshd
logpath  = ${logpath}
maxretry = 5
EOF

    systemctl enable --now fail2ban >/dev/null 2>&1
    systemctl restart fail2ban >/dev/null 2>&1
    sleep 1
    fail2ban-client unban --all >/dev/null 2>&1 || true

    log_info "fail2ban is protecting sshd (bantime=1h, maxretry=5)."
    log_info "Trusted (never banned): ${ignoreip}"
}
