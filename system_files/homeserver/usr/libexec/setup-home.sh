#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <username>" >&2
  exit 1
fi

TARGET_USER="$1"
HOME_DIR="/var/home/$TARGET_USER"

cd "$HOME_DIR"

# Install dotfiles from /usr/share/dotfiles
# Alternative: https://www.chezmoi.io/
dotfiles_sync(){
  rsync -a \
    --numeric-ids \
    --chmod=F644,D755 \
    --chown="${TARGET_USER}:${TARGET_USER}" \
    /usr/share/dotfiles/ "${HOME_DIR}/"

    # Ensure local bin is executable
    chmod -R +x "${HOME_DIR}/.local/bin"
}

# Setup OH-MY-BASH for user
install_ohmybash() {
  if [[ -f "/usr/local/share/oh-my-bash/bashrc" ]]; then
    # copy local
    cp /usr/local/share/oh-my-bash/bashrc "${HOME_DIR}/.bashrc"

    # modify .bashrc
    # https://github.com/ohmybash/oh-my-bash?tab=readme-ov-file
    sed -i 's/^plugins=(git)$/plugins=(git kubectl)/g' "${HOME_DIR}/.bashrc"
    echo 'export OMB_USE_SUDO=false' >> "${HOME_DIR}/.bashrc"
    echo 'export DISABLE_AUTO_UPDATE=true' >> "${HOME_DIR}/.bashrc"

    chown "$TARGET_USER":"$TARGET_USER" "${HOME_DIR}/.bashrc"
  fi
}

install_ohmybash
dotfiles_sync

echo "Finished setting up home for $TARGET_USER"
