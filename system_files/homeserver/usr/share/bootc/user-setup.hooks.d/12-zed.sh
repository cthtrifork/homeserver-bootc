#!/usr/bin/env bash
set -euo pipefail

# Setup ~/.local directories
mkdir -p "$HOME/.local/bin" "$HOME/.local/share/applications"

appid="dev.zed.Zed"

# Copy .desktop file
desktop_file_path="$HOME/.local/share/applications/${appid}.desktop"
src_dir="/usr/share/dotfiles/.local/zed.app/share/applications"
if [ -f "$src_dir/${appid}.desktop" ]; then
    cp "$src_dir/${appid}.desktop" "${desktop_file_path}"
    sed -i "s|Icon=zed|Icon=$HOME/.local/zed.app/share/icons/hicolor/512x512/apps/zed.png|g" "${desktop_file_path}"
    sed -i "s|Exec=zed|Exec=$HOME/.local/zed.app/bin/zed|g" "${desktop_file_path}"
fi

# Link the zed binary
if [ -f "$HOME/.local/zed.app/bin/zed" ]; then
    ln -sf "$HOME/.local/zed.app/bin/zed" "$HOME/.local/bin/zed"
fi

# The image owns Zed's version (pinned in build_files/gui/11-gui-zed-editor.sh, bumped by
# Renovate). The dotfiles rsync restores that copy on every boot, so a self-update would be
# undone anyway and could leave a mix of two versions. Turn the updater off instead.
# Only added when the user has not set auto_update themselves. settings.json is JSONC, so
# edit it as text: a trailing comma is allowed.
settings_dir="$HOME/.config/zed"
settings="$settings_dir/settings.json"
mkdir -p "$settings_dir"
if [ ! -s "$settings" ] || [ "$(tr -d "[:space:]" <"$settings")" = "{}" ]; then
    printf '{\n  "auto_update": false\n}\n' >"$settings"
elif ! grep -q '"auto_update"' "$settings"; then
    sed -i '0,/^{/s//{\n  "auto_update": false,/' "$settings"
fi
