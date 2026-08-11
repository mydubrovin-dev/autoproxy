#!/usr/bin/env bash
# Rebuilds /etc/squid/passwd from a plain-text user list and reloads Squid.
#
# Usage (as root):
#   autoproxy-squid-users [path-to-users-file]
#
# Default users file: /etc/autoproxy/squid-users.txt
# Format: one "username:password" per line. Blank lines and lines
# starting with # are ignored. Editing the file and re-running this
# script is the supported way to add/remove/change Squid logins —
# don't hand-edit /etc/squid/passwd, it gets fully rebuilt from the
# users file every time this runs (removed lines lose access).

set -euo pipefail

USERS_FILE="${1:-/etc/autoproxy/squid-users.txt}"
PASSWD_FILE="/etc/squid/passwd"

if [ "$(id -u)" -ne 0 ]; then
    echo "Run as root (sudo)." >&2
    exit 1
fi

if [ ! -f "$USERS_FILE" ]; then
    echo "Users file not found: $USERS_FILE" >&2
    exit 1
fi

command -v htpasswd >/dev/null 2>&1 || {
    echo "htpasswd not found (expected from the httpd-tools package, installed alongside squid)." >&2
    exit 1
}

tmp_passwd="$(mktemp)"
trap 'rm -f "$tmp_passwd"' EXIT

count=0
while IFS= read -r line || [ -n "$line" ]; do
    line="${line%%#*}"
    line="$(echo "$line" | xargs)"
    [ -z "$line" ] && continue

    user="${line%%:*}"
    pass="${line#*:}"

    if [ -z "$user" ] || [ -z "$pass" ] || [ "$user" = "$line" ]; then
        echo "Skipping malformed line: $line" >&2
        continue
    fi

    if [ "$count" -eq 0 ]; then
        htpasswd -bc "$tmp_passwd" "$user" "$pass" >/dev/null
    else
        htpasswd -b "$tmp_passwd" "$user" "$pass" >/dev/null
    fi
    count=$((count + 1))
done < "$USERS_FILE"

if [ "$count" -eq 0 ]; then
    echo "No valid user:password lines found in $USERS_FILE — refusing to lock everyone out." >&2
    exit 1
fi

install -o root -g squid -m 640 "$tmp_passwd" "$PASSWD_FILE"
echo "Loaded ${count} user(s) into ${PASSWD_FILE}."

if systemctl reload squid 2>/dev/null; then
    echo "squid reloaded."
elif systemctl restart squid 2>/dev/null; then
    echo "squid restarted (reload wasn't available)."
else
    echo "Could not reload/restart squid — check 'systemctl status squid'." >&2
    exit 1
fi
