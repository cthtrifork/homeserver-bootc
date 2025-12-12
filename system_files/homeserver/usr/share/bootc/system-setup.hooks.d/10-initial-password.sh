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

# If not local, fallback to creating a local user+group (so /etc/shadow can work)
if ! grep -q "^${TARGET_USER}:" /etc/passwd; then
  echo "user not in /etc/passwd, creating locally"

  if ! getent group "$TARGET_USER" >/dev/null 2>&1; then
    echo "creating group '$TARGET_USER' ($TARGET_ID)"
    groupadd -g "$TARGET_ID" "$TARGET_USER" || true
  fi

  if ! id "$TARGET_USER" >/dev/null 2>&1; then
    echo "creating user '$TARGET_USER' ($TARGET_ID)"
    useradd -u "$TARGET_ID" -g "$TARGET_ID" \
      -m -d "/home/$TARGET_USER" -s /bin/bash "$TARGET_USER" || true
  fi
else
  echo "user already present in /etc/passwd"
fi

echo "setting password"
echo "$TARGET_USER:Password" | chpasswd

# unlocking account if needed
usermod -U "$TARGET_USER" || true

touch "$FLAG"
