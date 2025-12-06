#!/usr/bin/bash
set -euo pipefail

trap '[[ $BASH_COMMAND != echo* ]] && [[ $BASH_COMMAND != log* ]] && echo "+ $BASH_COMMAND"' DEBUG

log() {
  echo "=== $* ==="
}

log "Enabling system services"
#systemctl --global enable podman-auto-update.timer
systemctl enable docker.socket
systemctl enable qemu-guest-agent
systemctl enable podman.socket
systemctl enable sshd.service
systemctl enable setup-groups.service
systemctl enable bootc-user-setup.service
systemctl enable bootc-system-setup.service
systemctl enable pinggy.service
systemctl enable setup-tmpfiles.service
systemctl enable systemd-userdbd.service

systemctl enable setup-home@caspertdk.service

# Enhance logging, but heavy in resources - journalctl is better alternative
systemctl disable rsyslog || true
