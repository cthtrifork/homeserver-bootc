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

    sudo chown "$USER":"$USER" "$HOME_DIR"/.bashrc
  fi
}

# Setup .gitconfig for user
configure_gitconfig() {
  if [[ -f "/home/$USER/.ssh/id_ed25519.pub" ]]; then
    cat <<EOT | tee /home/"$USER"/.gitconfig > /dev/null
  [user]
      name = Casper Thygesen
      email = cth@trifork.com
      signingkey = /home/$USER/.ssh/id_ed25519.pub
  [gpg]
      format = ssh
  [commit]
      gpgsign = true
  [init]
      defaultBranch = main
EOT
    sudo chown "$USER":"$USER" "$HOME_DIR"/.gitconfig
  fi
}

install_ohmybash
#upgrade_oh_my_bash
configure_gitconfig

echo "Finished setting up home for $USER"