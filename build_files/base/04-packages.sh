#!/usr/bin/bash

echo "::group:: ===$(basename "$0")==="

set -ouex pipefail

# All DNF-related operations should be done here whenever possible

# shellcheck source=build_files/shared/copr-helpers.sh
source /ctx/build_files/shared/copr-helpers.sh

# Use negativo17 for the multimedia stack. Fedora cannot ship patent-encumbered
# codecs, so its image carries a crippled mesa/va stack and no H.264/H.265/AAC.
# Classic used to get the replacements baked into the ublue base image; building
# on Fedora directly it has to pull them in itself.
#
# The repo file is not created here: ublue-os-akmods-addons, installed by
# 03-install-kernel-akmods.sh, owns negativo17-fedora-multimedia.repo, which
# declares repo id `fedora-multimedia`. Adding a second file declaring the same
# id is rejected by dnf, so only enable it. Note that `config-manager` does not
# edit that file - it writes /etc/dnf/repos.override.d/99-config_manager.repo,
# which 17-cleanup.sh removes and validate-repos.sh scans.
dnf config-manager setopt fedora-multimedia.enabled=1

# Two mechanisms are needed here, and they are not interchangeable.
#
# OVERRIDES are packages Fedora and negativo17 both ship under the SAME name,
# already installed from Fedora: `distro-sync` swaps them to negativo17's build.
# intel-vpl-gpu-rt is deliberately absent - negativo17 ships no vpl package for
# F44, so it stays Fedora's build.
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

# CODECS are the same software under a DIFFERENT name in each repo: Fedora ships
# ffmpeg-free / libav*-free / fdk-aac-free, negativo17 ships ffmpeg / libav* /
# libfdk-aac. `distro-sync` cannot bridge a rename - it only moves an installed
# name to another version of that same name - so these have to be installed, and
# the install replaces the -free builds. That rename is the whole reason the two
# lists cannot be merged into one.
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

# Priority is scoped to these two transactions. At 90 the repo shadows ~53
# Fedora package names, which must not be in effect for the bulk install below.
dnf config-manager setopt fedora-multimedia.priority=90
dnf distro-sync --skip-unavailable -y --repo='fedora-multimedia' "${OVERRIDES[@]}"
dnf -y install --enablerepo='fedora-multimedia' "${CODECS[@]}"
dnf config-manager unsetopt fedora-multimedia.priority

# Neither command's exit code can tell us the swap happened: distro-sync exits 0
# when negativo17 is unreachable (its repo file ships skip_if_unavailable=1) and
# when a package is simply not in the repo. Check the packages themselves.
for pkg in "${OVERRIDES[@]}" "${CODECS[@]}"; do
    if ! rpm -q --qf '%{vendor}' "$pkg" 2>/dev/null | grep -q negativo17; then
        echo "Multimedia override failed: ${pkg} did not come from negativo17." >&2
        exit 1
    fi
done
dnf versionlock add "${OVERRIDES[@]}" "${CODECS[@]}"

# Nothing after this point should resolve against negativo17.
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
