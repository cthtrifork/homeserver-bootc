#!/usr/bin/env bash
set -euo pipefail

FLAG=/etc/passwd.done
TARGET_USER="${TARGET_USER:?TARGET_USER not set}"
TARGET_ID="${TARGET_ID:?TARGET_ID not set}"

[[ -e "$FLAG" ]] && {
  echo "$TARGET_USER should already be configured with a password, skipping"
  exit 0
}

echo "configuring user '$TARGET_USER' (id $TARGET_ID)"

echo "setting password"
echo "$TARGET_USER:Password" | chpasswd

echo "unlocking account if needed"
usermod -U "$TARGET_USER" || true

touch "$FLAG"
echo "done"
