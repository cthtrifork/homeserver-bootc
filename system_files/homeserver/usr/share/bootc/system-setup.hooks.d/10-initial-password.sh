#!/usr/bin/env bash
set -euo pipefail

if [ ! -e /etc/passwd.done ]; then
    echo "Password" | passwd $TARGET_USER -s
fi

touch /etc/passwd.done

# lock out root user
if ! usermod -L root; then
    sed -i 's|^root.*|root:!:1::::::|g' /etc/shadow
fi
