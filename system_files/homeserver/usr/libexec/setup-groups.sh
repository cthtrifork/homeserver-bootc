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
for user in "${wheelarray[@]}"; do
  echo "Setting up home for user: $user"

  start=$((BASE + (i * STEP)))
  echo "$user:$start:$SIZE" | tee -a /etc/subuid /etc/subgid >/dev/null

  if ! grep -q "^$user:" /etc/passwd; then
    echo "[WARNING] Fixed user $user in /etc/passwd"
    getent passwd $user | sudo tee -a /etc/passwd
  fi

  usermod -aG docker "$user"

  echo "Password" | passwd $USER_NAME -s

  i=$((i + 1))
done

touch /etc/homeserver/setup-groups.done