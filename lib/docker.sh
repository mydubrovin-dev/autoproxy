#!/usr/bin/env bash
# Installs Docker Engine if it is not already present.

setup_docker() {
    if command -v docker >/dev/null 2>&1; then
        log_info "Docker already installed, skipping."
    else
        log_info "Installing Docker Engine..."
        curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
        sh /tmp/get-docker.sh >/dev/null
        rm -f /tmp/get-docker.sh
    fi

    systemctl enable --now docker >/dev/null 2>&1
    log_info "Docker is running."
}
