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
    -m -d "/home/$TARGET_USER" -s /bin/bash "$TARGET_USER" || true
else
  echo "local user already present in /etc/passwd"
fi

grep -q "^${TARGET_USER}:" /etc/group || {
  getent group "$TARGET_USER" >> /etc/group 2>/dev/null || groupadd -g "$TARGET_ID" "$TARGET_USER" || true
}

grep -q "^${TARGET_USER}:" /etc/passwd || {
  getent passwd "$TARGET_USER" >> /etc/passwd 2>/dev/null || \
    useradd -u "$TARGET_ID" -g "$TARGET_ID" -m -d "/home/$TARGET_USER" -s /bin/bash "$TARGET_USER" || true
}

echo "Synchronizing shadow databases (pwconv/grpconv)"
sudo pwconv
sudo grpconv

echo "Setting initial password"
echo "$TARGET_USER:Password" | chpasswd || echo "fail chpasswd"
#echo "Password" | passwd $TARGET_USER --stdin || echo "fail passwd"

echo "unlocking account if needed"
usermod -U "$TARGET_USER" || true

touch "$FLAG"
echo "done"
