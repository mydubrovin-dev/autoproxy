# Debian 13 (trixie) ships OpenSSL 3.5.x in its normal repos, which the
# MEKO SNI checker (menu [7], proxy_checker.py) requires for FakeTLS/
# SelfSteal domain validation (X25519MLKEM768 support). Getting this from
# the base image means no source build inside (or worse, outside) the
# container is ever needed.
FROM debian:13-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
        curl \
        ca-certificates \
        iptables \
        iproute2 \
        procps \
        sudo \
        nano \
        python3 \
        openssl \
    && rm -rf /var/lib/apt/lists/*

# telemt's own installer (github.com/telemt/telemt/install.sh, pulled in
# by MEKO's Telemt menu) requires $USER or $LOGNAME to literally be
# "root" when running as uid 0 — otherwise it dies with "Use 'su -' or
# 'sudo -i' to login under root". `docker exec` doesn't set either var by
# itself (there's no real login happening), so without this they're
# empty and the check trips regardless of how the container is entered.
ENV USER=root
ENV LOGNAME=root
ENV HOME=/root

# Without this, MEKO/telemt's unguarded `systemctl ...` calls (this
# container has no init system) fail with "command not found" and, since
# several of those call sites run under `set -e` (main.sh itself does),
# take the whole interactive menu down with them rather than just
# printing a warning. See systemctl-shim.sh for details.
COPY systemctl-shim.sh /usr/local/bin/systemctl
RUN chmod +x /usr/local/bin/systemctl

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
