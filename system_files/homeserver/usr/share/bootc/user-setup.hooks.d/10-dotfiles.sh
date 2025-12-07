#!/usr/bin/env bash
set -euo pipefail

TARGET_USER="$(whoami)"
HOME_DIR="/var/home/$TARGET_USER"

cd "$HOME_DIR"

# Install dotfiles from /usr/share/dotfiles
# Alternative: https://www.chezmoi.io/
dotfiles_sync() {
    rsync -a \
        --numeric-ids \
        --ignore-times \
        --chmod=F644,D755 \
        --chown="${TARGET_USER}:${TARGET_USER}" \
        /usr/share/dotfiles/ "${HOME_DIR}/"

    # Ensure local bin is executable
    chmod -R +x "${HOME_DIR}/.local/bin"
}

dotfiles_report() {
    rsync -av --delete --dry-run --stats --itemize-changes \
        --exclude=.vscode-server/ \
        --exclude=projects/ \
        --exclude=cache/ \
        --exclude=.cache/ \
        --exclude=.local/share/containers \
        /usr/share/dotfiles/ "${HOME_DIR}/"
}

dotfiles_sync

echo "Finished setting up dotfiles for $TARGET_USER"