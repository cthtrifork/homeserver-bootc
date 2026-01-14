#!/usr/bin/env bash

set -euo pipefail

TARGET_USER="$(whoami)"
HOME_DIR="/var/home/$TARGET_USER"

cd "$HOME_DIR"

# Setup OH-MY-BASH for user
install_ohmybash() {
    if [[ -f "/usr/local/share/oh-my-bash/bashrc" ]]; then
        # copy to oh-my-bash to local .bashrc
        cat /usr/local/share/oh-my-bash/bashrc >>"${HOME_DIR}/.bashrc"

        # modify .bashrc
        # https://github.com/ohmybash/oh-my-bash?tab=readme-ov-file
        sed -i 's/^plugins=(git)$/plugins=(git kubectl)/g' "${HOME_DIR}/.bashrc"

        chown "$TARGET_USER":"$TARGET_USER" "${HOME_DIR}/.bashrc"
    fi
}

install_ohmybash

echo "Finished setting up oh-my-bash for $TARGET_USER"
