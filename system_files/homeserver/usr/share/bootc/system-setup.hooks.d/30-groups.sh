#!/usr/bin/env bash
set -euo pipefail

ensure_group() {
    local group="$1"

    if getent group "$group" >/dev/null; then
        return 0
    fi

    echo "Creating system group: $group"
    groupadd --system "$group"
}

ensure_group docker
ensure_group libvirt
ensure_group kvm

mapfile -t wheelarray < <(getent group wheel | cut -d: -f4 | tr ',' '\n')
for user in "${wheelarray[@]}"; do
    [[ -n "$user" ]] || continue
    usermod -aG docker,libvirt,kvm "$user"
done
