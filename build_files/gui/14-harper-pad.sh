#!/usr/bin/bash

echo "::group:: ===$(basename "$0")==="

set -ouex pipefail

# Harper Pad desktop app, installed from the PGP-signed RPM of a GitHub release.
HARPER_PAD_VERSION="v2.7.1" # renovate: datasource=github-releases depName=cthtrifork/harper-pad

base="https://github.com/cthtrifork/harper-pad/releases/download/${HARPER_PAD_VERSION}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

curl -fsSL --retry 5 --retry-delay 5 --retry-all-errors -o "$tmp/key.asc" "${base}/harper-pad-release-key.asc"
curl -fsSL --retry 5 --retry-delay 5 --retry-all-errors -o "$tmp/harper-pad.rpm" "${base}/harper-pad_${HARPER_PAD_VERSION}_x86_64.rpm"

# Verify the signature against the release key before installing.
rpm --import "$tmp/key.asc"
rpmkeys --checksig "$tmp/harper-pad.rpm"
dnf -y install "$tmp/harper-pad.rpm"

echo "::endgroup::"
