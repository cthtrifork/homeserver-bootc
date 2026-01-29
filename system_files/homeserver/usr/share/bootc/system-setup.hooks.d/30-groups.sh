#!/usr/bin/env bash
set -euo pipefail

# Function to append a group entry to /etc/group
append_group() {
    local group_name="$1"
    if ! grep -q "^$group_name:" /etc/group; then
        echo "Appending $group_name to /etc/group"
        grep "^$group_name:" /usr/lib/group | tee -a /etc/group >/dev/null
    fi
}

# Setup Groups
append_group docker
append_group libvirt
append_group kvm

mapfile -t wheelarray < <(getent group wheel | cut -d ":" -f 4 | tr ',' '\n')
for user in "${wheelarray[@]}"; do
    usermod -aG libvirt,kvm,docker "$user"
done
