#!/usr/bin/env bash
set -e

MEKO_INSTALL_URL="https://raw.githubusercontent.com/Mekotofeuka/MTPROTO_FIX_By_MEKO/main/install.sh"
MEKO_MAIN="/opt/mtpr-simple/main.sh"

curl -fsSL "$MEKO_INSTALL_URL" -o /tmp/meko-install.sh
chmod +x /tmp/meko-install.sh

# /opt and /etc/telemt are named volumes (see lib/mtproto.sh), so a
# mekopr setup done in a previous container survives `docker rm -f` +
# recreate. If it's there, pick back up where it left off: MEKO/telemt
# have no systemd inside this container to reapply the SYN-FIX rules on
# boot with (there's no init system at all here), so we do that job
# ourselves on every container start instead — cheap and idempotent
# enough (harmless no-op if the rules are already live, e.g. on a plain
# container restart rather than a host reboot).
if [ -f "$MEKO_MAIN" ]; then
    echo "[autoproxy] Existing mekopr setup found — restoring 'mekopr' command and reapplying SYN-FIX..."
    ln -sf "$MEKO_MAIN" /usr/local/bin/mekopr
    "$MEKO_MAIN" -auto_install "${AUTOPROXY_MTPROTO_PORT:-443}" || \
        echo "[autoproxy] SYN-FIX reapply skipped/failed (likely already active) — check with: docker exec -it <container> mekopr"
fi

# telemt's own installer only *starts* the daemon via systemd or openrc
# (see install_service() upstream) — with neither available here, it
# just prints "start it yourself" and does nothing. Our systemctl shim
# stops that installer from crashing, but it doesn't make telemt
# actually run: nothing was ever listening. This loop is the real
# replacement for the systemd unit telemt wanted: check every 10s
# whether it's running, (re)launch it as the `telemt` user (created by
# telemt's own installer) if not. Runs for the lifetime of the
# container, independent of whatever mekopr's menu thinks "restart"
# means (which just calls the shimmed, no-op systemctl).
supervise_telemt() {
    local bin="/bin/telemt"
    local cfg="/etc/telemt/telemt.toml"
    while true; do
        if [ -x "$bin" ] && [ -f "$cfg" ] && id telemt >/dev/null 2>&1; then
            if ! pgrep -f "^${bin} ${cfg}\$" >/dev/null 2>&1; then
                echo "[autoproxy] telemt not running — starting it (logs: /var/log/telemt.log)"
                su -s /bin/sh telemt -c "${bin} ${cfg}" >>/var/log/telemt.log 2>&1 &
            fi
        fi
        sleep 10
    done
}
supervise_telemt &

cat <<EOF
======================================================================
 autoproxy: MTProto-fix container is up.

 This container ships curl + iptables + the MEKO installer, ready to
 run, but the MEKO menu itself is interactive (proxy type, apply fix,
 SNI check) so it must be run once by hand:

   docker exec -it <container-name> bash /tmp/meko-install.sh

 Menu: install a proxy -> [1] Apply MTProto FIX -> [7] Check SNI
 Recommended SNI domain: www.ite-ng.ru

 /opt and /etc/telemt persist in named Docker volumes, so that setup
 survives container recreation. The telemt binary itself (/bin) does
 not — if missing after a recreate, just reinstall it from the Telemt
 menu (Enter for latest version), it takes a few seconds.

 telemt itself is supervised by this entrypoint (checked/restarted
 every 10s) since there's no systemd/openrc in here for it to use —
 see the README for why, and the same for MTG/MTProto.zig if you
 switch engines (not currently supervised the same way).
======================================================================
EOF

exec tail -f /dev/null
