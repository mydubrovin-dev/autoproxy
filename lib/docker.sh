#!/usr/bin/env bash
# Installs Docker Engine if it is not already present.

setup_docker() {
    if command -v docker >/dev/null 2>&1; then
        log_info "Docker already installed, skipping."
    else
        log_info "Installing Docker Engine..."
        # get.docker.com mis-detects Rocky/Alma and points dnf at a
        # nonexistent download.docker.com/linux/rocky/ repo. Docker's own
        # docs have RHEL-family distros use the CentOS repo instead, so we
        # set that up directly rather than relying on the convenience script.
        pkg_install dnf-plugins-core >/dev/null
        "$PKG_MGR" config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo >/dev/null
        pkg_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >/dev/null
    fi

    systemctl enable docker >/dev/null 2>&1
    # Always a hard restart, not just enable --now (which is a no-op if
    # docker is already running from a previous install.sh run).
    # ensure_firewalld/disable_ipv6 run before this and restart
    # firewalld; firewalld restarting *after* docker has already set up
    # its bridge NAT/masquerade rules wipes them, breaking outbound
    # connectivity (DNS included) for anything on the default bridge
    # network — which is exactly what `docker build`'s build sandbox
    # uses, regardless of the app container's own --network host.
    # Restarting docker here makes it reinstall those rules fresh every
    # run instead of silently rotting after repeated re-runs.
    systemctl restart docker
    log_info "Docker is running."
}
