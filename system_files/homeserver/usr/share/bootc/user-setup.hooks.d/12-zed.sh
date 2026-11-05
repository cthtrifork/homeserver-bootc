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

# Auto-install the Harper grammar checker extension (https://writewithharper.com/docs/integrations/zed).
# Only seeds a fresh config so an existing Zed settings.json is never overwritten.
zed_settings="$HOME/.config/zed/settings.json"
if [ ! -e "$zed_settings" ]; then
    mkdir -p "$(dirname "$zed_settings")"
    printf '{\n  "auto_install_extensions": {\n    "harper": true\n  }\n}\n' >"$zed_settings"
fi
