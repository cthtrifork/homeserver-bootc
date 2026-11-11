#!/usr/bin/bash

echo "::group:: ===$(basename "$0")==="

set -ouex pipefail

# KGlance, the KDE popup with the clock, the date and the battery (shortcut Meta+Alt+G), installed from the RPM of a
# GitHub release. The rpm adds an autostart entry that starts it hidden at login, so the shortcut works right away.
KGLANCE_VERSION="v0.2.0" # renovate: datasource=github-releases depName=cthtrifork/kglance

base="https://github.com/cthtrifork/kglance/releases/download/${KGLANCE_VERSION}"
rpm_name="kglance-${KGLANCE_VERSION#v}-1.x86_64.rpm"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

curl -fsSL --retry 5 --retry-delay 5 --retry-all-errors -o "$tmp/SHA256SUMS" "${base}/SHA256SUMS"
curl -fsSL --retry 5 --retry-delay 5 --retry-all-errors -o "$tmp/${rpm_name}" "${base}/${rpm_name}"

# The rpm is not PGP-signed (the release carries build-provenance attestations instead), so check it against the
# release's SHA256SUMS before installing. A missing line is an error, not a skipped check.
(cd "$tmp" && grep -F " ${rpm_name}" SHA256SUMS | sha256sum -c -)
dnf -y install "$tmp/${rpm_name}"

echo "::endgroup::"
