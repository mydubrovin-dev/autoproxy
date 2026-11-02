#!/usr/bin/env bash
set -e

MEKO_INSTALL_URL="https://raw.githubusercontent.com/Mekotofeuka/MTPROTO_FIX_By_MEKO/main/install.sh"
MEKO_MAIN="/opt/mtpr-simple/main.sh"

curl -fsSL "$MEKO_INSTALL_URL" -o /tmp/meko-install.sh
chmod +x /tmp/meko-install.sh

# /opt (named volume) and /etc/telemt (host bind mount) — see lib/mtproto.sh — so a
# mekopr setup done in a previous container survives `docker rm -f` +
# recreate. If it's there, restore the `mekopr` command.
if [ -f "$MEKO_MAIN" ]; then
    ln -sf "$MEKO_MAIN" /usr/local/bin/mekopr
fi

# MEKO's SYN-FIX normally persists via a systemd unit
# (mtpr-nft-synfix.service / mtpr-synfix.service) whose ExecStart just
# runs a script MEKO saved under /opt/mtpr-simple. There's no systemd in
# this container, so those units never start. Run the saved script
# ourselves on every container start instead — it's what the unit would
# have done, it honours whichever variant was picked in the menu
# (nftables vs iptables), and it's idempotent (the nft script drops and
# recreates its own table; the iptables one flushes its own chain). On a
# plain container restart the rules are already live and this is a
# no-op; after a host reboot (kernel netfilter state wiped) it restores
# protection.
reapply_synfix() {
    local nft_script="/opt/mtpr-simple/mtpr-synfix-nft.sh"
    local ipt_script="/opt/mtpr-simple/apply-mtpr-synfix.sh"
    if [ -f "$nft_script" ]; then
        echo "[autoproxy] Reapplying SYN-FIX (nftables) from $nft_script"
        /bin/sh "$nft_script" || echo "[autoproxy] nftables SYN-FIX reapply failed — check: docker exec -it <container> mekopr"
    elif [ -f "$ipt_script" ]; then
        echo "[autoproxy] Reapplying SYN-FIX (iptables) from $ipt_script"
        bash "$ipt_script" || echo "[autoproxy] iptables SYN-FIX reapply failed — check: docker exec -it <container> mekopr"
    else
        echo "[autoproxy] No saved SYN-FIX script under /opt/mtpr-simple — nothing to reapply (apply it once via mekopr menu [1])."
    fi
}
reapply_synfix

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

 /opt persists in a named Docker volume and /etc/telemt is the same
 directory on the host, so that setup survives container recreation. The telemt binary itself (/bin) does
 not — if missing after a recreate, just reinstall it from the Telemt
 menu (Enter for latest version), it takes a few seconds.

 telemt itself is supervised by this entrypoint (checked/restarted
 every 10s) since there's no systemd/openrc in here for it to use —
 see the README for why, and the same for MTG/MTProto.zig if you
 switch engines (not currently supervised the same way).
======================================================================
EOF

exec tail -f /dev/null
