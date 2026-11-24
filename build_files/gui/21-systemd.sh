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

# Virtualization (virt-manager): libvirt's modular daemons are socket-activated but none are enabled by default.
# Enabling a base socket also enables its -ro and -admin sockets (Also=).
systemctl enable virtqemud.socket virtnetworkd.socket virtstoraged.socket virtnodedevd.socket virtnwfilterd.socket virtsecretd.socket

# Power management
systemctl enable tlp.service
systemctl enable tlp-pd.service
# disable rf-kill to avoid known conflicts on reboots
systemctl mask systemd-rfkill.service systemd-rfkill.socket

# startup speed improvements
systemctl mask systemd-networkd-wait-online.service
