#!/usr/bin/env bash
set -e

MEKO_INSTALL_URL="https://raw.githubusercontent.com/Mekotofeuka/MTPROTO_FIX_By_MEKO/main/install.sh"
MEKO_MAIN="/opt/mtpr-simple/main.sh"

# Not fatal: on a plain `docker restart` the previous copy is still in
# /tmp, and a GitHub hiccup must not put the container into a restart
# loop (which would take telemt down with it).
curl -fsSL "$MEKO_INSTALL_URL" -o /tmp/meko-install.sh.new \
    && mv /tmp/meko-install.sh.new /tmp/meko-install.sh \
    || echo "[autoproxy] Could not fetch the MEKO installer (offline?) — continuing."
chmod +x /tmp/meko-install.sh 2>/dev/null || true

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
#
# The telemt binary (/bin/telemt), its system user and its file
# capability live in the container's own writable layer, which
# `docker rm` (i.e. every install.sh run) throws away — leaving /etc/telemt
# intact but nothing to run. So the loop also keeps a copy of the binary
# on the persisted /opt volume, and restore_telemt() below puts it back
# (with the same user/uid and setcap) when the container is recreated.
TELEMT_PERSIST_DIR="/opt/.autoproxy"
TELEMT_PERSIST_BIN="${TELEMT_PERSIST_DIR}/telemt"

restore_telemt() {
    [ -x /bin/telemt ] && return 0
    [ -f "$TELEMT_PERSIST_BIN" ] || return 0
    echo "[autoproxy] telemt binary missing (container was recreated) — restoring from ${TELEMT_PERSIST_BIN}"
    cp -p "$TELEMT_PERSIST_BIN" /bin/telemt
    chmod 755 /bin/telemt

    if ! id telemt >/dev/null 2>&1; then
        # Reuse the numeric uid/gid that already own /etc/telemt (it's a
        # host bind mount, so they survived), falling back to fresh
        # system ids if those are taken.
        local uid gid nologin
        uid="$(stat -c %u /etc/telemt 2>/dev/null || echo 0)"
        gid="$(stat -c %g /etc/telemt 2>/dev/null || echo 0)"
        nologin="$(command -v nologin || echo /bin/false)"
        if [ "$gid" != 0 ]; then groupadd -r -g "$gid" telemt 2>/dev/null || groupadd -r telemt; else groupadd -r telemt; fi
        if [ "$uid" != 0 ]; then
            useradd -r -u "$uid" -g telemt -d /opt/telemt -s "$nologin" -c "Telemt Proxy" telemt 2>/dev/null \
                || useradd -r -g telemt -d /opt/telemt -s "$nologin" -c "Telemt Proxy" telemt
        else
            useradd -r -g telemt -d /opt/telemt -s "$nologin" -c "Telemt Proxy" telemt
        fi
    fi
    mkdir -p /opt/telemt
    chown telemt:telemt /opt/telemt /etc/telemt
    chmod 750 /opt/telemt /etc/telemt
    [ -f /etc/telemt/telemt.toml ] && chown root:telemt /etc/telemt/telemt.toml && chmod 640 /etc/telemt/telemt.toml

    # Same capabilities telemt's installer grants when there's no systemd
    # (needed to bind :443 as a non-root user).
    if command -v setcap >/dev/null 2>&1; then
        setcap cap_net_bind_service,cap_net_admin=+ep /bin/telemt 2>/dev/null || true
    fi
}
restore_telemt || echo "[autoproxy] restoring telemt failed — reinstall it from the mekopr Telemt menu."

supervise_telemt() {
    local bin="/bin/telemt"
    local cfg="/etc/telemt/telemt.toml"
    while true; do
        # Keep the persisted copy current (installer put a new/updated one).
        if [ -x "$bin" ] && { [ ! -f "$TELEMT_PERSIST_BIN" ] || [ "$bin" -nt "$TELEMT_PERSIST_BIN" ]; }; then
            mkdir -p "$TELEMT_PERSIST_DIR" \
                && cp -p "$bin" "${TELEMT_PERSIST_BIN}.tmp" \
                && mv -f "${TELEMT_PERSIST_BIN}.tmp" "$TELEMT_PERSIST_BIN"
        fi
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
 directory on the host, so that setup survives container recreation.
 The telemt binary (/bin) is copied to /opt/.autoproxy within ~10s of
 being installed and restored (with its user and capabilities) when the
 container is recreated. If it was never installed, or was installed
 by an older version of this image, install it once from the Telemt
 menu (Enter for latest version) — it takes a few seconds.

 telemt itself is supervised by this entrypoint (checked/restarted
 every 10s) since there's no systemd/openrc in here for it to use —
 see the README for why, and the same for MTG/MTProto.zig if you
 switch engines (not currently supervised the same way).
======================================================================
EOF

exec tail -f /dev/null
