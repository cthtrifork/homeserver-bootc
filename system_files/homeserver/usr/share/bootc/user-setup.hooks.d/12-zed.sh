#!/usr/bin/env bash
set -euo pipefail

# Link the zed binary
if [ -f "$HOME/.local/zed$suffix.app/bin/zed" ]; then
    ln -sf "$HOME/.local/zed$suffix.app/bin/zed" "$HOME/.local/bin/zed"
fi
