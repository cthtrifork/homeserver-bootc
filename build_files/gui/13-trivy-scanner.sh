#!/usr/bin/env bash
set -euo pipefail

trap '[[ $BASH_COMMAND != echo* ]] && [[ $BASH_COMMAND != log* ]] && echo "+ $BASH_COMMAND"' DEBUG

log() {
    echo "=== $* ==="
}

debug() {
    echo "[DEBUG] $*" >&2
}

echo "::group:: ===$(basename "$0")==="

# Trivy Scanner: Wails GUI that scans container images with Trivy running in podman.
# The release asset is a dynamically linked binary (GTK4 + WebKitGTK 6), see packages-added.
REPO="cthtrifork/trivy-dashboard-wail3"
BINARY_NAME="trivy-scanner"
TRIVY_SCANNER_VERSION="v0.2.0" # renovate: datasource=github-releases depName=cthtrifork/trivy-dashboard-wail3

ARCH_NAME="$(uname -m)"
[[ "$ARCH_NAME" == "x86_64" ]] || {
    echo "trivy-scanner is only released for x86_64, got $ARCH_NAME" >&2
    exit 1
}

ASSET="${BINARY_NAME}_linux_amd64"
BASE_URL="https://github.com/${REPO}/releases/download/${TRIVY_SCANNER_VERSION}"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

log "Downloading ${BINARY_NAME} ${TRIVY_SCANNER_VERSION}..."
curl -sfL "${BASE_URL}/${ASSET}" -o "${TMP_DIR}/${ASSET}"
curl -sfL "${BASE_URL}/SHA256SUMS" -o "${TMP_DIR}/SHA256SUMS"

debug "Verifying checksum..."
(cd "${TMP_DIR}" && grep -E " \*?${ASSET}\$" SHA256SUMS | sha256sum -c -)

INSTALL_DIR="/usr/local/bin"
debug "Installing to ${INSTALL_DIR}..."
install -D -m 0755 "${TMP_DIR}/${ASSET}" "${INSTALL_DIR}/${BINARY_NAME}"

# Application menu entry
install -d /usr/share/applications
cat >/usr/share/applications/trivy-scanner.desktop <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Trivy Scanner
Comment=Scan container images for vulnerabilities with Trivy
Exec=/usr/local/bin/trivy-scanner
Icon=security-medium
Terminal=false
Categories=Development;Security;
DESKTOP

log "Successfully installed ${BINARY_NAME} ${TRIVY_SCANNER_VERSION} to ${INSTALL_DIR}!"

echo "::endgroup::"
