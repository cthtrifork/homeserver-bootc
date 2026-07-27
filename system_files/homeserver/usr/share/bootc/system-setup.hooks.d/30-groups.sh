#!/usr/bin/env bash
set -euo pipefail

ensure_group() {
    local group="$1"

    if getent group "$group" >/dev/null; then
        echo "[DEBUG] System group: $group exists. Skipping"
        return 0
    fi

    echo "[INFO] Creating system group: $group"
    groupadd "$group"
}

ensure_group docker
ensure_group libvirt
ensure_group kvm

echo "Configuring groups all users in group wheel"

mapfile -t wheelarray < <(getent group wheel | cut -d: -f4 | tr ',' '\n')
for user in "${wheelarray[@]}"; do
    [[ -n "$user" ]] || continue
    usermod -aG docker "$user"
    usermod -aG libvirt "$user"
    usermod -aG kvm "$user"
    echo "Added user: $user to standard system groups"
done
