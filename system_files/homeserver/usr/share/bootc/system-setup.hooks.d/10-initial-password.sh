#!/usr/bin/env bash
set -euo pipefail

#exit 0 # solved by homectl firstboot instead

FLAG=/etc/passwd.done
TARGET_USER="${TARGET_USER:?TARGET_USER not set}"
TARGET_ID="${TARGET_ID:?TARGET_ID not set}"

[[ -e "$FLAG" ]] && {
  echo "$TARGET_USER should already be configured with a password, skipping"
  exit 0
}

echo "configuring user '$TARGET_USER' (id $TARGET_ID)"

authselect select local with-silent-lastlog --force

# Ensure the local group exists
if ! grep -q "^${TARGET_USER}:" /etc/group; then
  echo "creating local group '$TARGET_USER' ($TARGET_ID)"
  groupadd -g "$TARGET_ID" "$TARGET_USER" || true
else
  echo "local group already present in /etc/group"
fi

# Ensure the local user exists
if ! grep -q "^${TARGET_USER}:" /etc/passwd; then
  echo "creating local user '$TARGET_USER' ($TARGET_ID)"
  useradd -u "$TARGET_ID" -g "$TARGET_ID" \
    -m -d "/var/home/$TARGET_USER" -s /bin/bash "$TARGET_USER" || true
else
  echo "local user already present in /etc/passwd"
fi

echo "setting password"
echo "$TARGET_USER:Password" | chpasswd || echo "fail chossswd"
echo "Password" | passwd $TARGET_USER --stdin || echo "fail passwd"

echo "unlocking account if needed"
usermod -U "$TARGET_USER" || true

touch "$FLAG"
echo "done"
