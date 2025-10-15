#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <username>" >&2
  exit 1
fi

USER="$1"
HOME_DIR="/home/$USER"

cd "$HOME_DIR"

# Setup OH-MY-BASH for user
install_ohmybash() {
  if [[ -f "/usr/local/share/oh-my-bash/bashrc" ]]; then
    # copy local
    cp /usr/local/share/oh-my-bash/bashrc "$HOME_DIR"/.bashrc

    # modify .bashrc
    # https://github.com/ohmybash/oh-my-bash?tab=readme-ov-file
    sed -i 's/^plugins=(git)$/plugins=(git kubectl)/g' "$HOME_DIR"/.bashrc
    echo 'export OMB_USE_SUDO=false' >> "$HOME_DIR"/.bashrc
    echo 'export DISABLE_AUTO_UPDATE=true' >> "$HOME_DIR"/.bashrc

    chown "$USER":"$USER" "$HOME_DIR"/.bashrc
  fi

  if [[ ! -f "$HOME_DIR"/.bash_profile ]]; then
    echo 'source ~/.bashrc;' | tee "$HOME_DIR"/.bash_profile >/dev/null
    chown "$USER":"$USER" "$HOME_DIR"/.bash_profile
  fi
}

install_ohmybash

echo "Finished setting up home for $USER"
