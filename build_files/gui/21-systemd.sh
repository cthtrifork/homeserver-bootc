#!/usr/bin/bash
set -euo pipefail

trap '[[ $BASH_COMMAND != echo* ]] && [[ $BASH_COMMAND != log* ]] && echo "+ $BASH_COMMAND"' DEBUG

log() {
    echo "=== $* ==="
}

# We dont want pinggy running on the gui container
systemctl disable pinggy.service

# The laptop is not a cluster VM: it must not poll the Update VMs page
systemctl disable vm-upgrade-poll.timer

log "Enabling system services"

# GUI
systemctl set-default graphical.target

# Power management
systemctl enable tlp.service
systemctl enable tlp-pd.service
# disable rf-kill to avoid known conflicts on reboots
systemctl mask systemd-rfkill.service systemd-rfkill.socket

# startup speed improvements
systemctl mask systemd-networkd-wait-online.service
