#!/usr/bin/bash
set -euo pipefail

trap '[[ $BASH_COMMAND != echo* ]] && [[ $BASH_COMMAND != log* ]] && echo "+ $BASH_COMMAND"' DEBUG

log() {
    echo "=== $* ==="
}

# We dont want pinggy running on the gui container
systemctl disable pinggy.service

log "Enabling system services"

# Power management
systemctl enable tlp.service
systemctl enable tlp-pd.service
# disable rf-kill to avoid known conflicts on reboots
systemctl mask systemd-rfkill.service systemd-rfkill.socket

# startup speed improvements
systemctl mask systemd-networkd-wait-online.service

# Enhance logging, but heavy in resources - journalctl is better alternative
systemctl disable rsyslog || true
