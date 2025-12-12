#!/usr/bin/env bash
set -euo pipefail

FLAG=/etc/passwd.done
TARGET_USER="${TARGET_USER:?TARGET_USER not set}"
UID_GID=1010 # todo: less magic strings somehow

[[ -e "$FLAG" ]] && exit 0

# Wait up to 30s for sysusers to possibly populate /etc/passwd
for i in {1..60}; do
  grep -q "^${TARGET_USER}:" /etc/passwd && break
  sleep 0.5
done

# If not local, create a local user+group (so /etc/shadow can work)
if ! grep -q "^${TARGET_USER}:" /etc/passwd; then
  getent group "$TARGET_USER" >/dev/null 2>&1 || groupadd -g "$UID_GID" "$TARGET_USER" || true
  id "$TARGET_USER" >/dev/null 2>&1 || useradd -u "$UID_GID" -g "$UID_GID" -m -d "/home/$TARGET_USER" -s /bin/bash "$TARGET_USER" || true
  usermod -aG wheel "$TARGET_USER" || true
fi

# Set default password (creates/updates /etc/shadow entry)
echo "$TARGET_USER:Password" | chpasswd

# Unlock if needed
usermod -U "$TARGET_USER" || true

touch "$FLAG"
