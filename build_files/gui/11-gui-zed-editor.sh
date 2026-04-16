#!/usr/bin/env bash
set -euo pipefail

trap '[[ $BASH_COMMAND != echo* ]] && [[ $BASH_COMMAND != log* ]] && echo "+ $BASH_COMMAND"' DEBUG

log() {
    echo "=== $* ==="
}

debug() {
    echo "[DEBUG] $*" >&2
}

# Copied from https://zed.dev/install.sh
# Downloads a tarball from https://zed.dev/releases and unpacks it
# into ~/.local/.

echo "::group:: ===$(basename "$0")==="

ZED_VERSION="0.232.2" # renovate: datasource=github-releases depName=zed-industries/zed

platform="$(uname -s)" # Linux
arch="$(uname -m)"     # x86_64
ZED_VERSION="${ZED_VERSION:-latest}"

log "Installing zed-editor $ZED_VERSION..."

# Use TMPDIR if available (for environments with non-standard temp directories)
if [ -n "${TMPDIR:-}" ] && [ -d "${TMPDIR}" ]; then
    temp="$(mktemp -d "$TMPDIR/zed-XXXXXX")"
else
    temp="$(mktemp -d "/tmp/zed-XXXXXX")"
fi

debug "Downloading Zed version: $ZED_VERSION"
curl -sfL "https://cloud.zed.dev/releases/stable/$ZED_VERSION/download?asset=zed&arch=$arch&os=linux&source=install.sh" >"$temp/zed-linux-$arch.tar.gz"

# Unpack
INSTALL_DIR=/usr/share/dotfiles/.local
rm -rf "$INSTALL_DIR/zed.app"
mkdir -p "$INSTALL_DIR/zed.app"
tar -xzf "$temp/zed-linux-$arch.tar.gz" -C "$INSTALL_DIR/"

echo "::endgroup::"
