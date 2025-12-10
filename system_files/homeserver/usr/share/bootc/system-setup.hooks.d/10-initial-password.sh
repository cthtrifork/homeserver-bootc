#!/usr/bin/env bash
set -euo pipefail

if [ ! -e /etc/passwd.done ]; then
    # Set default password
    echo "$TARGET_USER:Password" | chpasswd
    # ensure the account is unlocked
    usermod -U $TARGET_USER || true
	#chage -E $(date -d "+1 days" +%Y-%m-%d) $TARGET_USER # force password change on next login
fi

touch /etc/passwd.done

# lock out root user
#if ! usermod -L root; then
#    sed -i 's|^root.*|root:!:1::::::|g' /etc/shadow
#fi
