#!/usr/bin/env bash
set -euo pipefail

# SCRIPT VERSION - bump to force re-run
ROOTLESS_SETUP_VER=1
ROOTLESS_SETUP_VER_FILE="/etc/homeserver/rootless-setup"

mkdir -p /etc/homeserver

if [[ -f "$ROOTLESS_SETUP_VER_FILE" && "$(cat "$ROOTLESS_SETUP_VER_FILE")" == "$ROOTLESS_SETUP_VER" ]]; then
    echo "Rootless setup has already run at version $ROOTLESS_SETUP_VER. Skipping."
    exit 0
fi

echo "Configuring subuid/subgid for $TARGET_USER"

touch /etc/subuid /etc/subgid
usermod --add-subuid 100000-165535 --add-subgid 100000-165535 $TARGET_USER

podman system migrate
restorecon -R -F /var/lib/containers

echo "$ROOTLESS_SETUP_VER" >"$ROOTLESS_SETUP_VER_FILE"
echo "Rootless setup completed."
