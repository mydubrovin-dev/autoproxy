#!/usr/bin/env bash
# Builds and runs the MEKO MTProto-fix container.
#
# The upstream installer (github.com/Mekotofeuka/MTPROTO_FIX_By_MEKO) is a
# menu-driven, interactive tool with no flags/env vars for unattended use.
# We therefore only automate the container plumbing here; the actual proxy
# type / SNI domain selection is done once, interactively, via `mekopr`
# inside the container after this script finishes.

MTPROTO_CONTAINER_NAME="autoproxy-mtproto"
MTPROTO_IMAGE_NAME="autoproxy/mtproto-fix"

deploy_mtproto() {
    log_info "Building MTProto-fix container image..."
    docker build -t "$MTPROTO_IMAGE_NAME" "$INSTALL_DIR/docker/mtproto" >/dev/null

    if docker ps -a --format '{{.Names}}' | grep -qx "$MTPROTO_CONTAINER_NAME"; then
        log_warn "Container ${MTPROTO_CONTAINER_NAME} already exists, recreating it."
        docker rm -f "$MTPROTO_CONTAINER_NAME" >/dev/null
    fi

    log_info "Starting MTProto-fix container (host network, NET_ADMIN)..."
    docker run -d \
        --name "$MTPROTO_CONTAINER_NAME" \
        --network host \
        --cap-add NET_ADMIN \
        --restart unless-stopped \
        "$MTPROTO_IMAGE_NAME" >/dev/null

    log_info "MTProto-fix container is running as '${MTPROTO_CONTAINER_NAME}'."
    cat <<EOF

--------------------------------------------------------------------
  MTProto proxy setup (one manual step required):

    docker exec -it ${MTPROTO_CONTAINER_NAME} bash /tmp/meko-install.sh

  In the menu:
    1. Install/select your proxy (Telemt, MTG or MTProto.zig)
    2. Apply "MTProto FIX" (menu option [1])
    3. Check SNI (menu option [7]) and use this domain:

         www.ite-ng.ru

  Re-open the menu any time with:
    docker exec -it ${MTPROTO_CONTAINER_NAME} mekopr
--------------------------------------------------------------------
EOF
}
