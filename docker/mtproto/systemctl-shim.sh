#!/bin/sh
# Minimal systemctl shim for this systemd-less container.
#
# MEKO/telemt call `systemctl daemon-reload`/`enable`/`restart` (and
# similar) as plain, unguarded commands to persist services across
# reboots. Several call sites run under `set -e` (main.sh itself does),
# so with no `systemctl` binary at all those calls fail with "command
# not found" (exit 127) and take the whole interactive menu down with
# them — not just a warning, an actual crash back to the shell.
#
# Real persistence is handled separately by entrypoint.sh, which
# reapplies the SYN-FIX on every container start (see lib/mtproto.sh /
# README for why: no init system here to run a real systemd unit with).
# This shim's only job is to make MEKO/telemt's systemctl calls succeed
# instead of crashing the script that made them.
case "$1" in
    is-active | is-enabled)
        # MEKO's menu header asks systemctl whether its SYN-FIX "service"
        # is running and prints "Таблица есть, сервис не запущен" when the
        # answer is no. The "service" is just the netfilter rules, so
        # answer from reality: active iff the rules are actually loaded.
        svc=""
        for a in "$@"; do
            case "$a" in
                -* | is-active | is-enabled) ;;
                *) svc="$a" ;;
            esac
        done
        case "$svc" in
            mtpr-nft-synfix | mtpr-nft-synfix.service)
                nft list table inet mtpr_synfix >/dev/null 2>&1 && exit 0
                ;;
            mtpr-synfix | mtpr-synfix.service)
                iptables -t filter -S MTPR_SYNFIX >/dev/null 2>&1 && exit 0
                ;;
        esac
        # Everything else: "not active/enabled" in systemctl's own
        # exit-code convention, so status-check logic behaves sanely.
        exit 3
        ;;
    *)
        exit 0
        ;;
esac
