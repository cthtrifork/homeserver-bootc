#!/usr/bin/env bash
set -euo pipefail


if [[ ! -e /etc/passwd.done ]]; then
    # Set default password
    echo "$TARGET_USER:Password" | chpasswd
    STATUS=$?
    echo "chpasswd for $TARGET_USER received exit code: $STATUS"
    # ensure the account is unlocked
    usermod -U $TARGET_USER || true
    # force password change on next login
    #chage -d 0 $TARGET_USER

    touch /etc/passwd.done
fi

# lock out root user
#if ! usermod -L root; then
#    sed -i 's|^root.*|root:!:1::::::|g' /etc/shadow
#fi
