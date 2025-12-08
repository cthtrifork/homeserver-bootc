#!/usr/bin/env bash
set -euo pipefail

echo "Configuring subuid/subgid for $TARGET_USER"

touch /etc/subuid /etc/subgid
usermod --add-subuid 100000-165535 --add-subgid 100000-165535 $TARGET_USER

podman system migrate

sudo restorecon -R -F /var/lib/containers