#!/usr/bin/env bash
set -euo pipefail

TARGET_USER=caspertdk

if [ ! -e /etc/passwd.done ]; then
    # hack
    echo "Password" | passwd $TARGET_USER -s
    # Set default password
    echo "$TARGET_USER:Password" | chpasswd
    # ensure the account is unlocked
    usermod -U $TARGET_USER || true
    # force password change on next login
    chage -d 0 $TARGET_USER
fi

touch /etc/passwd.done

# lock out root user
#if ! usermod -L root; then
#    sed -i 's|^root.*|root:!:1::::::|g' /etc/shadow
#fi
