#!/usr/bin/bash

echo "::group:: ===$(basename "$0")==="

set -eoux pipefail

IMPORTANT_PACKAGES_DX=(
    code
    flatpak-builder
    libvirt
    qemu
)

# Docker CE below Fedora 45, Fedora's own packages from 45 on (see 00-dx.sh)
if [[ "$FEDORA_MAJOR_VERSION" -lt 45 ]]; then
    IMPORTANT_PACKAGES_DX+=(
        containerd.io
        docker-ce
        docker-buildx-plugin
        docker-compose-plugin
    )
else
    IMPORTANT_PACKAGES_DX+=(
        containerd
        docker-buildx
        docker-cli
        docker-compose
        moby-engine
    )
fi

for package in "${IMPORTANT_PACKAGES_DX[@]}"; do
    rpm -q "${package}" >/dev/null || { echo "Missing package: ${package}... Exiting"; exit 1 ; }
done

IMPORTANT_UNITS=(
    docker.socket
    podman.socket
)

for unit in "${IMPORTANT_UNITS[@]}"; do
    if ! systemctl is-enabled "$unit" 2>/dev/null | grep -q "^enabled$"; then
        echo "${unit} is not enabled"
        exit 1
    fi
done

echo "::endgroup::"
