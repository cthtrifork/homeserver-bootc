#!/usr/bin/env bash
set -euo pipefail

FLAG=/etc/passwd.done

# Run only once
if [[ -e "$FLAG" ]]; then
  exit 0
fi

: "${TARGET_USER:?TARGET_USER not set}"

# Make sure the user exists (created by systemd-sysusers)
if ! getent passwd "$TARGET_USER" >/dev/null 2>&1; then
  echo "Initial password: user '$TARGET_USER' does not exist yet; aborting" >&2
  exit 1
fi

# Set default password
echo "$TARGET_USER:Password" | chpasswd
STATUS=$?
echo "chpasswd for $TARGET_USER received exit code: $STATUS"

if [[ $STATUS -ne 0 ]]; then
  echo "Initial password: chpasswd failed; not marking as done" >&2
  exit $STATUS
fi

# Ensure the account is unlocked (in case sysusers locked it)
usermod -U "$TARGET_USER" || true

# Only mark as done if everything above succeeded
touch "$FLAG"
