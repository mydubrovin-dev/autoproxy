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

    systemctl enable --now docker >/dev/null 2>&1
    log_info "Docker is running."
}
