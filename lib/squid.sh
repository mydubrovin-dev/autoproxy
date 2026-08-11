#!/usr/bin/env bash
# Installs and configures Squid as an authenticated forward proxy.

setup_squid() {
    log_info "Installing Squid..."
    pkg_install squid httpd-tools >/dev/null

    local user="${AUTOPROXY_SQUID_USER:-proxyuser}"
    local pass="${AUTOPROXY_SQUID_PASS:-$(random_password 20)}"
    local port="${AUTOPROXY_SQUID_PORT:-3128}"

    local auth_helper
    for candidate in /usr/lib64/squid/basic_ncsa_auth /usr/lib/squid/basic_ncsa_auth /usr/libexec/squid/basic_ncsa_auth; do
        if [ -x "$candidate" ]; then
            auth_helper="$candidate"
            break
        fi
    done
    if [ -z "$auth_helper" ]; then
        log_err "Could not locate basic_ncsa_auth helper after installing squid."
        exit 1
    fi

    htpasswd -bc /etc/squid/passwd "$user" "$pass" >/dev/null
    chown root:squid /etc/squid/passwd
    chmod 640 /etc/squid/passwd

    # /etc/autoproxy/squid-users.txt is the source of truth for logins
    # going forward (see scripts/squid-users.sh) — only seed it on first
    # install so re-running install.sh never clobbers users added later.
    mkdir -p /etc/autoproxy
    if [ ! -f /etc/autoproxy/squid-users.txt ]; then
        cat > /etc/autoproxy/squid-users.txt <<EOF
# One "username:password" per line. Blank lines and lines starting
# with # are ignored. After editing, apply with:
#   autoproxy-squid-users
${user}:${pass}
EOF
        chmod 600 /etc/autoproxy/squid-users.txt
    fi

    install -m 755 "$INSTALL_DIR/scripts/squid-users.sh" /usr/local/bin/autoproxy-squid-users

    cat > /etc/squid/squid.conf <<EOF
http_port ${port}

auth_param basic program ${auth_helper} /etc/squid/passwd
auth_param basic realm autoproxy
auth_param basic credentialsttl 2 hours

acl authenticated proxy_auth REQUIRED
acl SSL_ports port 443
acl Safe_ports port 80
acl Safe_ports port 443
acl Safe_ports port 1025-65535
acl CONNECT method CONNECT

http_access deny !Safe_ports
http_access deny CONNECT !SSL_ports
http_access allow authenticated
http_access deny all

coredump_dir /var/spool/squid
refresh_pattern ^ftp:           1440    20%     10080
refresh_pattern ^gopher:        1440    0%      1440
refresh_pattern -i (/cgi-bin/|\?) 0     0%      0
refresh_pattern .                0      20%     4320

visible_hostname autoproxy
EOF

    systemctl enable --now squid >/dev/null 2>&1

    firewalld_open_port "$port"

    umask 077
    mkdir -p /root/autoproxy
    cat > /root/autoproxy/squid-credentials.txt <<EOF
Squid forward proxy credentials
  Host port : ${port}
  Username  : ${user}
  Password  : ${pass}
EOF
    chmod 600 /root/autoproxy/squid-credentials.txt

    log_info "Squid is up on port ${port}. Credentials saved to /root/autoproxy/squid-credentials.txt"
}
