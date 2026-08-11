#!/usr/bin/env bash
# Installs and configures fail2ban to protect SSH from brute-force attempts.

setup_fail2ban() {
    log_info "Installing fail2ban..."

    if [ "$PKG_MGR" = "dnf" ] && ! rpm -q epel-release >/dev/null 2>&1; then
        pkg_install epel-release >/dev/null 2>&1 || true
    fi
    pkg_install fail2ban >/dev/null

    local logpath="/var/log/secure"
    [ -f /var/log/auth.log ] && logpath="/var/log/auth.log"

    cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
bantime  = 1h
findtime = 10m
maxretry = 5
backend  = systemd

[sshd]
enabled  = true
port     = ssh
filter   = sshd
logpath  = ${logpath}
maxretry = 5
EOF

    systemctl enable --now fail2ban >/dev/null 2>&1

    log_info "fail2ban is protecting sshd (bantime=1h, maxretry=5)."
}
