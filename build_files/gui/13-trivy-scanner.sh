#!/usr/bin/bash

echo "::group:: ===$(basename "$0")==="

set -ouex pipefail

# Trivy Scanner desktop app, installed from the PGP-signed RPM of a GitHub release.
TRIVY_SCANNER_VERSION="v1.9.0" # renovate: datasource=github-releases depName=cthtrifork/trivy-dashboard-wail3

base="https://github.com/cthtrifork/trivy-dashboard-wail3/releases/download/${TRIVY_SCANNER_VERSION}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

curl -fsSL --retry 5 --retry-delay 5 --retry-all-errors -o "$tmp/key.asc" "${base}/trivy-scanner-release-key.asc"
curl -fsSL --retry 5 --retry-delay 5 --retry-all-errors -o "$tmp/trivy-scanner.rpm" "${base}/trivy-scanner_${TRIVY_SCANNER_VERSION}_x86_64.rpm"

# Verify the signature against the release key before installing.
rpm --import "$tmp/key.asc"
rpmkeys --checksig "$tmp/trivy-scanner.rpm"
dnf -y install "$tmp/trivy-scanner.rpm"

echo "::endgroup::"
