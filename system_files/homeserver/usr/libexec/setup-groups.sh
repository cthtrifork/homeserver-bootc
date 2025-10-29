#!/usr/bin/env bash
set -euo pipefail

mkdir -p /etc/homeserver

if [[ -f /etc/homeserver/setup-groups.done ]]; then
  echo "Groups already set up, skipping."
  exit 0
fi

# Setup Groups
wheelarray=($(getent group wheel | cut -d: -f4 |  tr ',' '\n'))

BASE=1000000
STEP=100000
SIZE=65536

mv /etc/subuid /etc/subuid.bak
mv /etc/subgid /etc/subgid.bak 

# Setup home directory for each user in wheel group
i=0
for USER_NAME in "${wheelarray[@]}"; do
  echo "Setting up home for user: $USER_NAME"

  start=$((BASE + (i * STEP)))
  echo "$USER_NAME:$start:$SIZE" | tee -a /etc/subuid /etc/subgid >/dev/null

  if ! grep -q "^$USER_NAME:" /etc/passwd; then
    echo "[WARNING] Fixed user $USER_NAME in /etc/passwd"
    getent passwd $USER_NAME | sudo tee -a /etc/passwd
  fi

  usermod -aG docker "$USER_NAME"

  echo "Password" | passwd $USER_NAME -s

  i=$((i + 1))
done

touch /etc/homeserver/setup-groups.done