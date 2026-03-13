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

ZED_VERSION="v0.227.1" # renovate: datasource=github-releases depName=zed-industries/zed

platform="$(uname -s)"
arch="$(uname -m)"
channel="${ZED_CHANNEL:-stable}"
ZED_VERSION="${ZED_VERSION:-latest}"

log "Installing zed-editor $ZED_VERSION..."

# Use TMPDIR if available (for environments with non-standard temp directories)
if [ -n "${TMPDIR:-}" ] && [ -d "${TMPDIR}" ]; then
    temp="$(mktemp -d "$TMPDIR/zed-XXXXXX")"
else
    temp="$(mktemp -d "/tmp/zed-XXXXXX")"
fi

arch="x86_64"

debug "Downloading Zed version: $ZED_VERSION"
curl -sfL "https://cloud.zed.dev/releases/$channel/$ZED_VERSION/download?asset=zed&arch=$arch&os=linux&source=install.sh" > "$temp/zed-linux-$arch.tar.gz"

suffix=""
if [ "$channel" != "stable" ]; then
    suffix="-$channel"
fi

appid=""
case "$channel" in
    stable)
    appid="dev.zed.Zed"
    ;;
    nightly)
    appid="dev.zed.Zed-Nightly"
    ;;
    preview)
    appid="dev.zed.Zed-Preview"
    ;;
    dev)
    appid="dev.zed.Zed-Dev"
    ;;
    *)
    debug "Unknown release channel: ${channel}. Using stable app ID."
    appid="dev.zed.Zed"
    ;;
esac

# Unpack
HOME=usr/share/dotfiles # hack
rm -rf "$HOME/.local/zed$suffix.app"
mkdir -p "$HOME/.local/zed$suffix.app"
tar -xzf "$temp/zed-linux-$arch.tar.gz" -C "$HOME/.local/"

# Setup ~/.local directories
mkdir -p "$HOME/.local/bin" "$HOME/.local/share/applications"

# Link the binary
if [ -f "$HOME/.local/zed$suffix.app/bin/zed" ]; then
    ln -sf "$HOME/.local/zed$suffix.app/bin/zed" "$HOME/.local/bin/zed"
else
    # support for versions before 0.139.x.
    ln -sf "$HOME/.local/zed$suffix.app/bin/cli" "$HOME/.local/bin/zed"
fi

# Copy .desktop file
desktop_file_path="$HOME/.local/share/applications/${appid}.desktop"
src_dir="$HOME/.local/zed$suffix.app/share/applications"
if [ -f "$src_dir/${appid}.desktop" ]; then
    cp "$src_dir/${appid}.desktop" "${desktop_file_path}"
else
    # Fallback for older tarballs
    cp "$src_dir/zed$suffix.desktop" "${desktop_file_path}"
fi
sed -i "s|Icon=zed|Icon=$HOME/.local/zed$suffix.app/share/icons/hicolor/512x512/apps/zed.png|g" "${desktop_file_path}"
sed -i "s|Exec=zed|Exec=$HOME/.local/zed$suffix.app/bin/zed|g" "${desktop_file_path}"

echo "::endgroup::"