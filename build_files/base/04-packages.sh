#!/usr/bin/bash

echo "::group:: ===$(basename "$0")==="

set -ouex pipefail

# All DNF-related operations should be done here whenever possible

# shellcheck source=build_files/shared/copr-helpers.sh
source /ctx/build_files/shared/copr-helpers.sh

# Multimedia stack from negativo17, as Fedora can't ship patent encumbered codecs.
# The repo file comes with ublue-os-akmods-addons. config-manager writes to
# /etc/dnf/repos.override.d rather than the repo file, 17-cleanup.sh removes it.
dnf config-manager setopt fedora-multimedia.enabled=1

# Same package name in both repos, distro-sync moves these over.
# intel-vpl-gpu-rt is not in negativo17 for F44 and stays Fedora's.
OVERRIDES=(
    intel-gmmlib
    intel-mediasdk
    libheif
    libva
    libva-intel-media-driver
    mesa-dri-drivers
    mesa-filesystem
    mesa-libEGL
    mesa-libGL
    mesa-libgbm
    mesa-vulkan-drivers
)

# Fedora only ships these as -free builds (ffmpeg-free, libav*-free, fdk-aac-free),
# distro-sync can't cross a rename so they are installed and replace the -free ones.
CODECS=(
    ffmpeg
    ffmpeg-libs
    libavcodec
    libfdk-aac
    intel-vaapi-driver
    libva-utils
    pipewire-libs-extra
    libde265
    uvg266-libs
    vvdec-libs
)

# Fedora's libheif recommends libheif-ffmpeg, which requires Fedora's exact libheif build
# and keeps distro-sync from moving libheif over. negativo17 has no such subpackage.
dnf -y remove libheif-ffmpeg

# Priority only for these two transactions, at 90 the repo shadows ~53 Fedora packages.
# --enablerepo rather than --repo so dependencies can still resolve from Fedora.
dnf config-manager setopt fedora-multimedia.priority=90
dnf distro-sync --skip-unavailable -y --enablerepo='fedora-multimedia' "${OVERRIDES[@]}"
dnf -y install --enablerepo='fedora-multimedia' "${CODECS[@]}"
dnf config-manager unsetopt fedora-multimedia.priority

# distro-sync exits 0 when the repo is unreachable, so check the packages themselves
for package in "${OVERRIDES[@]}" "${CODECS[@]}"; do
    rpm -q --qf "%{NAME} %{VENDOR}" "${package}" | grep -q "negativo17\.org" || { echo "${package} not from negativo17... Exiting"; exit 1 ; }
done
dnf versionlock add "${OVERRIDES[@]}" "${CODECS[@]}"
dnf config-manager setopt fedora-multimedia.enabled=0

# NOTE:
# Packages are split into FEDORA_PACKAGES and COPR_PACKAGES to prevent
# malicious COPRs from injecting fake versions of Fedora packages.
# Fedora packages are installed first in bulk (safe).
# COPR packages are installed individually with isolated enablement.

# Base packages from Fedora repos - common to all versions
FEDORA_PACKAGES=(
    adcli
    adw-gtk3-theme
    adwaita-fonts-all
    autofs
    bash-color-prompt
    bcache-tools
    bootc
    borgbackup
    containerd
    cryfs
    davfs2
    ddcutil
    evtest
    fastfetch
    firewall-config
    fish
    foo2zjs
    fuse-encfs
    gcc
    gcc-c++
    git-credential-libsecret
    glow
    gnome-tweaks
    gum
    hplip
    ibus-mozc
    ifuse
    igt-gpu-tools
    input-remapper
    iwd
    jetbrains-mono-fonts-all
    just
    krb5-workstation
    libappindicator-gtk3
    libayatana-appindicator-gtk3
    libgda
    libgda-sqlite
    libimobiledevice
    libratbag-ratbagd
    libxcrypt-compat
    lm_sensors
    make
    mesa-libGLU
    mozc
    nautilus-gsconnect
    oddjob-mkhomedir
    opendyslexic-fonts
    openssh-askpass
    powerstat
    powertop
    printer-driver-brlaser
    pulseaudio-utils
    python3-pip
    python3-pygit2
    rclone
    restic
    samba
    samba-dcerpc
    samba-ldb-ldap-modules
    samba-winbind-clients
    samba-winbind-modules
    setools-console
    sssd-nfs-idmap
    switcheroo-control
    tmux
    usbip
    usbmuxd
    waypipe
    wireguard-tools
    wl-clipboard
    xdg-terminal-exec
    xprop
    zenity
    zsh
)
# Version-specific Fedora package additions
case "$FEDORA_MAJOR_VERSION" in
    42)
        FEDORA_PACKAGES+=(
            evolution-ews-core
            uld
        )
        ;;
    43)
        FEDORA_PACKAGES+=(
            evolution-ews-core
            gnupg2-scdaemon
        )
        ;;
    44)
        FEDORA_PACKAGES+=(
            gnupg2-scdaemon
        )
        ;;
esac

# Install all Fedora packages (bulk - safe from COPR injection)
echo "Installing ${#FEDORA_PACKAGES[@]} packages from Fedora repos..."
dnf -y install "${FEDORA_PACKAGES[@]}"

dnf config-manager addrepo --from-repofile=https://pkgs.tailscale.com/stable/fedora/tailscale.repo
dnf config-manager setopt tailscale-stable.enabled=0
dnf -y install --enablerepo='tailscale-stable' tailscale

# From che/nerd-fonts
copr_install_isolated "che/nerd-fonts" "nerd-fonts"

# From ublue-os/packages
copr_install_isolated "ublue-os/packages" "uupd"
copr_install_isolated "ublue-os/packages" "gnome-rounded-blur"

# Version-specific COPR packages
# case "$FEDORA_MAJOR_VERSION" in
#    42)
        # bazaar and uupd from ublue-os/packages
        # copr_install_isolated "ublue-os/packages" "bazaar" "uupd"
        # ;;
    # 43)
        # bazaar from ublue-os/packages
        # copr_install_isolated "ublue-os/packages" "bazaar"
        # ;;
# esac

# Packages to exclude - common to all versions
EXCLUDED_PACKAGES=(
    cosign
    fedora-bookmarks
    fedora-chromium-config
    fedora-chromium-config-gnome
    firefox
    firefox-langpacks
    gnome-extensions-app
    gnome-shell-extension-background-logo
    gnome-software
    gnome-software-rpm-ostree
    gnome-terminal-nautilus
    podman-docker
    yelp
)

# Remove excluded packages if they are installed
if [[ "${#EXCLUDED_PACKAGES[@]}" -gt 0 ]]; then
    readarray -t INSTALLED_EXCLUDED < <(rpm -qa --queryformat='%{NAME}\n' "${EXCLUDED_PACKAGES[@]}" 2>/dev/null || true)
    if [[ "${#INSTALLED_EXCLUDED[@]}" -gt 0 ]]; then
        dnf -y remove "${INSTALLED_EXCLUDED[@]}"
    else
        echo "No excluded packages found to remove."
    fi
fi

## Pins and Overrides
## Use this section to pin packages in order to avoid regressions
# Remember to leave a note with rationale/link to issue for each pin!
#
# Example:
#if [ "$FEDORA_MAJOR_VERSION" -eq "41" ]; then
#    Workaround pkcs11-provider regression, see issue #1943
#    rpm-ostree override replace https://bodhi.fedoraproject.org/updates/FEDORA-2024-dd2e9fb225
#fi

echo "::endgroup::"
