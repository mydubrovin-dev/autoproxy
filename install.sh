#!/usr/bin/env bash
# autoproxy bootstrap installer.
#
# Usage (on a fresh CentOS/Rocky/RHEL VPS, as root):
#   curl -fsSL https://raw.githubusercontent.com/mydubrovin-dev/autoproxy/main/install.sh | sudo bash
#
# Sets up:
#   - Squid forward proxy with login/password auth
#   - MTProto-fix (github.com/Mekotofeuka/MTPROTO_FIX_By_MEKO) in Docker
#   - fail2ban protecting sshd
#
# Override defaults via env vars, e.g.:
#   AUTOPROXY_SQUID_USER=alice AUTOPROXY_SQUID_PASS=secret AUTOPROXY_SQUID_PORT=8080 \
#     curl -fsSL .../install.sh | sudo bash

set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root (use sudo)." >&2
    exit 1
fi

REPO_RAW_BASE="https://raw.githubusercontent.com/mydubrovin-dev/autoproxy/main"
INSTALL_DIR="/opt/autoproxy"
FILES=(
    lib/common.sh
    lib/security.sh
    lib/squid.sh
    lib/fail2ban.sh
    lib/docker.sh
    lib/mtproto.sh
    docker/mtproto/Dockerfile
    docker/mtproto/entrypoint.sh
)

fetch_remote_files() {
    command -v curl >/dev/null 2>&1 || { echo "curl is required." >&2; exit 1; }
    mkdir -p "$INSTALL_DIR/lib" "$INSTALL_DIR/docker/mtproto"
    for f in "${FILES[@]}"; do
        curl -fsSL "${REPO_RAW_BASE}/${f}" -o "${INSTALL_DIR}/${f}"
    done
}

# If run from a local checkout (e.g. for development/testing), use the
# files next to this script instead of downloading them.
SCRIPT_DIR=""
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

if [ -n "$SCRIPT_DIR" ] && [ -d "$SCRIPT_DIR/lib" ]; then
    INSTALL_DIR="$SCRIPT_DIR"
else
    fetch_remote_files
fi

export INSTALL_DIR
# shellcheck source=lib/common.sh
source "$INSTALL_DIR/lib/common.sh"
# shellcheck source=lib/security.sh
source "$INSTALL_DIR/lib/security.sh"
# shellcheck source=lib/squid.sh
source "$INSTALL_DIR/lib/squid.sh"
# shellcheck source=lib/fail2ban.sh
source "$INSTALL_DIR/lib/fail2ban.sh"
# shellcheck source=lib/docker.sh
source "$INSTALL_DIR/lib/docker.sh"
# shellcheck source=lib/mtproto.sh
source "$INSTALL_DIR/lib/mtproto.sh"

log_info "Starting autoproxy install on $(source /etc/os-release; echo "$PRETTY_NAME")..."

ensure_firewalld
disable_ipv6
setup_squid
setup_fail2ban
setup_docker
deploy_mtproto

log_info "All done."
echo
echo "Summary:"
echo "  - IPv6                : disabled"
echo "  - firewalld            : running, fail2ban bans through it (not raw iptables)"
echo "  - Squid forward proxy : port ${AUTOPROXY_SQUID_PORT:-3128}, credentials in /root/autoproxy/squid-credentials.txt"
echo "  - fail2ban            : protecting sshd (bantime=1h, maxretry=5)"
echo "  - MTProto-fix         : container '${MTPROTO_CONTAINER_NAME}' — finish setup with the command printed above"
