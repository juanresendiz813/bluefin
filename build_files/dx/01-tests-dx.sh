#!/usr/bin/bash

echo "::group:: ===$(basename "$0")==="

set -eoux pipefail

IMPORTANT_PACKAGES_DX=(
    code
    containerd.io
    docker-ce
    docker-buildx-plugin
    docker-compose-plugin
    flatpak-builder
    libvirt
    qemu
)

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

# Verify home directory types in the installed SELinux policy.
# SEE:
#   https://github.com/ublue-os/bluefin/issues/4976
#   https://github.com/ublue-os/bluefin/discussions/4928
check_selinux_type() {
    local path="$1" expected_type="$2" context actual_type

    # These paths need not exist; explicitly look up directory contexts.
    if ! context=$(matchpathcon -N -n -m dir "${path}"); then
        echo "Failed to look up SELinux context for ${path}"
        exit 1
    fi

    # Compare only the type in user:role:type:range.
    actual_type="${context#*:*:}"
    actual_type="${actual_type%%:*}"
    if [[ "${actual_type}" != "${expected_type}" ]]; then
        echo "Unexpected SELinux type for ${path}: expected ${expected_type}, got ${context}"
        exit 1
    fi
}

check_selinux_type /var/home/testuser user_home_dir_t
check_selinux_type /var/home/testuser/.ssh ssh_home_t
check_selinux_type /var/home/testuser/Documents user_home_t
check_selinux_type /var/home/testuser/Music audio_home_t

echo "::endgroup::"
