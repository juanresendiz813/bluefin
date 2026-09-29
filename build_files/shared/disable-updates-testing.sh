#!/usr/bin/bash

echo "::group:: ===$(basename "$0")==="

set -eoux pipefail

# Pre-release Fedora ships updates-testing enabled; only beta images keep it on.
# Runs after the last package install and right before validate-repos.sh, so
# every dnf call still sees the package versions the pre-release base was built from.
if [[ "${UBLUE_IMAGE_TAG}" != "beta" ]]; then
    for repo_file in /etc/yum.repos.d/fedora-updates-testing.repo /usr/share/dnf5/repos.d/fedora-updates-testing.repo; do
        if [[ -f "$repo_file" ]]; then
            sed -i 's@enabled=1@enabled=0@g' "$repo_file"
        fi
    done
fi

echo "::endgroup::"
