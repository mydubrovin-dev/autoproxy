#!/usr/bin/env bash
set -e

MEKO_INSTALL_URL="https://raw.githubusercontent.com/Mekotofeuka/MTPROTO_FIX_By_MEKO/main/install.sh"

curl -fsSL "$MEKO_INSTALL_URL" -o /tmp/meko-install.sh
chmod +x /tmp/meko-install.sh

cat <<'EOF'
======================================================================
 autoproxy: MTProto-fix container is up.

 This container ships curl + iptables + the MEKO installer, ready to
 run, but the MEKO menu itself is interactive (proxy type, apply fix,
 SNI check) so it must be run once by hand:

   docker exec -it <container-name> bash /tmp/meko-install.sh

 Menu: install a proxy -> [1] Apply MTProto FIX -> [7] Check SNI
 Recommended SNI domain: www.ite-ng.ru
======================================================================
EOF

exec tail -f /dev/null
