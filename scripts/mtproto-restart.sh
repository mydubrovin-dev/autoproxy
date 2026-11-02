#!/usr/bin/env bash
# Validates /etc/telemt/telemt.toml, restarts the MTProto container so the
# config (e.g. newly added users) takes effect, and shows whether Telemt
# came back up.
#
# Usage (as root):
#   autoproxy-mtproto-restart           validate, restart the container
#   autoproxy-mtproto-restart --soft    validate, only restart the telemt
#                                       process (container, SYN-FIX and
#                                       other connections stay untouched)
#   autoproxy-mtproto-restart --check   only validate the config
#   autoproxy-mtproto-restart --force   restart even if validation fails
#
# Env: AUTOPROXY_TELEMT_CONF (default /etc/telemt/telemt.toml)

set -uo pipefail

NAME="autoproxy-mtproto"
CONF="${AUTOPROXY_TELEMT_CONF:-/etc/telemt/telemt.toml}"
MODE="restart"
FORCE=0

for arg in "$@"; do
    case "$arg" in
        --soft) MODE="soft" ;;
        --check) MODE="check" ;;
        --force) FORCE=1 ;;
        -h | --help) sed -n '2,15p' "$0"; exit 0 ;;
        *) echo "Unknown option: $arg" >&2; exit 2 ;;
    esac
done

errors=0
err() { echo "  [x] $*" >&2; errors=$((errors + 1)); }
ok()  { echo "  [+] $*"; }

validate_config() {
    echo "Checking $CONF ..."
    if [ ! -f "$CONF" ]; then
        err "config not found: $CONF (is Telemt installed? mekopr -> [3] -> Telemt -> [1])"
        return
    fi

    # tls_domain must be a plain hostname. Pasting a rendered markdown link
    # ("[www.x.ru](https://www.x.ru)") into the installer once broke
    # every client with "Unknown TLS SNI".
    local domain
    domain="$(sed -n 's/^[[:space:]]*tls_domain[[:space:]]*=[[:space:]]*"\(.*\)".*/\1/p' "$CONF" | head -1)"
    if [ -z "$domain" ]; then
        err "tls_domain is not set"
    elif [[ ! "$domain" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]]; then
        err "tls_domain is not a plain hostname: \"$domain\""
    else
        ok "tls_domain = $domain"
    fi

    # [access.users]: unique names, 32-hex secrets.
    local users
    users="$(awk '
        /^[[:space:]]*\[access\.users\]/ { f = 1; next }
        /^[[:space:]]*\[/                { f = 0 }
        f && /^[[:space:]]*[^#[:space:]].*=/ { print }
    ' "$CONF")"

    if [ -z "$users" ]; then
        err "[access.users] has no users"
        return
    fi

    local count=0 line name secret
    while IFS= read -r line; do
        name="$(echo "${line%%=*}" | xargs)"
        secret="$(echo "${line#*=}" | tr -d ' \t"')"
        count=$((count + 1))
        if [[ ! "$secret" =~ ^[0-9a-fA-F]{32}$ ]]; then
            err "user ${name}: secret must be exactly 32 hex chars (got ${#secret}: ${secret:0:12}...). A full tg key is ee+secret+domain — cut it, see README"
        fi
    done <<< "$users"

    local dups
    dups="$(echo "$users" | sed 's/=.*//' | tr -d ' \t"' | sort | uniq -d)"
    if [ -n "$dups" ]; then
        err "duplicate user names (TOML will not parse): $(echo "$dups" | tr '\n' ' ')"
    fi

    [ "$errors" -eq 0 ] && ok "${count} user(s), secrets look valid"
}

validate_config

if [ "$errors" -gt 0 ]; then
    if [ "$MODE" = "check" ] || [ "$FORCE" -ne 1 ]; then
        echo "Config has problems — not restarting (use --force to restart anyway)." >&2
        exit 1
    fi
    echo "Continuing because of --force."
fi

[ "$MODE" = "check" ] && { echo "Config OK."; exit 0; }

if [ "$(id -u)" -ne 0 ]; then
    echo "Run as root (sudo)." >&2
    exit 1
fi
command -v docker >/dev/null 2>&1 || { echo "docker not found." >&2; exit 1; }
if ! docker ps -a --format '{{.Names}}' | grep -qx "$NAME"; then
    echo "Container $NAME does not exist — run install.sh first." >&2
    exit 1
fi

if [ "$MODE" = "soft" ]; then
    echo "Restarting the telemt process (container keeps running)..."
    docker exec "$NAME" pkill -x telemt 2>/dev/null || echo "  (telemt was not running)"
    # The supervisor loop in the container's entrypoint relaunches it
    # within ~10s.
else
    echo "Restarting container $NAME ..."
    docker restart "$NAME" >/dev/null
fi

port="$(awk '/^[[:space:]]*\[server\]/{f=1;next} /^[[:space:]]*\[/{f=0} f && /^[[:space:]]*port[[:space:]]*=/{gsub(/[^0-9]/,"",$0); print; exit}' "$CONF" 2>/dev/null)"
port="${port:-443}"

echo "Waiting for telemt on port ${port} (up to 60s)..."
up=0
for _ in $(seq 1 30); do
    if docker exec "$NAME" pgrep -f "^/bin/telemt " >/dev/null 2>&1 \
        && ss -tln 2>/dev/null | grep -q ":${port} "; then
        up=1
        break
    fi
    sleep 2
done

echo
echo "--- last lines of /var/log/telemt.log ---"
docker exec "$NAME" tail -n 15 /var/log/telemt.log 2>/dev/null || echo "(no log yet)"
echo "-----------------------------------------"

if [ "$up" -eq 1 ]; then
    echo "OK: telemt is running and listening on port ${port}."
else
    echo "FAILED: telemt is not up on port ${port}." >&2
    if ! docker exec "$NAME" test -x /bin/telemt 2>/dev/null; then
        echo "  /bin/telemt is missing in the container and there is no saved copy in /opt/.autoproxy to restore." >&2
        echo "  Reinstall it: docker exec -it $NAME mekopr  ->  [3] -> Telemt -> [1] -> Enter" >&2
    else
        echo "  Read the log above; run 'autoproxy-mtproto-restart --check' to re-validate the config." >&2
    fi
    exit 1
fi
