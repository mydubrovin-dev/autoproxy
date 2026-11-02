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

# MEKO/telemt store their state across a few different paths. The ones
# worth keeping are persisted outside the container so that re-running
# install.sh (which always `docker rm -f`s and recreates this container
# to pick up image changes) doesn't wipe out a manual mekopr setup:
#   /opt        - named volume: MEKO manager (/opt/mtpr-simple), telemt
#                 workdir, MTProto.zig (/opt/mtproto-proxy)
#   /etc/telemt - bind mount of the SAME path on the host, so telemt's
#                 config/secrets (telemt.toml) can be read and edited
#                 directly on the host (and are obvious to back up),
#                 not buried under /var/lib/docker/volumes/...
# Deliberately NOT volume-mounting /bin (where telemt's own binary
# lands): on Debian 13 /bin is a symlink into /usr/bin (merged-usr), and
# mounting a volume there risks shadowing every base binary in the
# image. Re-fetching the telemt binary itself is one menu keypress
# ("Установить/обновить/откатить Telemt" -> Enter) — cheap to redo,
# unlike losing the manager or telemt's secrets.
# MTG's single-file /etc/mtg.toml also isn't covered (not worth a
# volume for one file) — only matters if you switch engines away from
# Telemt/MTProto.zig.
MTPROTO_VOLUME_OPT="autoproxy-mtproto-opt"
MTPROTO_TELEMT_ETC_DIR="/etc/telemt"
# Earlier versions kept /etc/telemt in this named volume instead.
MTPROTO_LEGACY_VOLUME_ETC_TELEMT="autoproxy-mtproto-etc-telemt"

# One-time move from the old named volume to the host directory: only if
# the old volume exists and the host dir is still empty, so it never
# overwrites anything and re-runs are no-ops. The old volume is left in
# place (harmless; `docker volume rm` it once you've checked).
migrate_telemt_etc() {
    mkdir -p "$MTPROTO_TELEMT_ETC_DIR"
    if docker volume inspect "$MTPROTO_LEGACY_VOLUME_ETC_TELEMT" >/dev/null 2>&1 \
        && [ -z "$(ls -A "$MTPROTO_TELEMT_ETC_DIR" 2>/dev/null)" ]; then
        local old
        old="$(docker volume inspect -f '{{ .Mountpoint }}' "$MTPROTO_LEGACY_VOLUME_ETC_TELEMT")"
        if [ -n "$(ls -A "$old" 2>/dev/null)" ]; then
            log_info "Migrating telemt config from Docker volume ${MTPROTO_LEGACY_VOLUME_ETC_TELEMT} to ${MTPROTO_TELEMT_ETC_DIR}..."
            cp -a "$old"/. "$MTPROTO_TELEMT_ETC_DIR"/
        fi
    fi
}

deploy_mtproto() {
    log_info "Building MTProto-fix container image..."
    docker build -t "$MTPROTO_IMAGE_NAME" "$INSTALL_DIR/docker/mtproto" >/dev/null

    migrate_telemt_etc

    install -m 755 "$INSTALL_DIR/scripts/mtproto-restart.sh" /usr/local/bin/autoproxy-mtproto-restart

    if docker ps -a --format '{{.Names}}' | grep -qx "$MTPROTO_CONTAINER_NAME"; then
        log_warn "Container ${MTPROTO_CONTAINER_NAME} already exists, recreating it (its mekopr setup is kept in the /opt volume and ${MTPROTO_TELEMT_ETC_DIR})."
        docker rm -f "$MTPROTO_CONTAINER_NAME" >/dev/null
    fi

    log_info "Starting MTProto-fix container (host network, NET_ADMIN)..."
    docker run -d \
        --name "$MTPROTO_CONTAINER_NAME" \
        --network host \
        --cap-add NET_ADMIN \
        --restart unless-stopped \
        -v "${MTPROTO_VOLUME_OPT}:/opt" \
        -v "${MTPROTO_TELEMT_ETC_DIR}:/etc/telemt:z" \
        "$MTPROTO_IMAGE_NAME" >/dev/null

    # --network host means telemt binds directly to the host's socket,
    # but that traffic still has to clear firewalld's own zone rules to
    # get there in the first place — this was missing entirely before,
    # so telemt could be up and listening and still be unreachable from
    # outside.
    firewalld_open_port "${AUTOPROXY_MTPROTO_PORT:-443}"

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
