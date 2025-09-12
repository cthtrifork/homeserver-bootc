#!/usr/bin/bash
#shellcheck disable=SC2115
set -eou pipefail

trap '[[ $BASH_COMMAND != echo* ]] && [[ $BASH_COMMAND != log* ]] && echo "+ $BASH_COMMAND"' DEBUG

log() {
  echo "=== $* ==="
}

log "Starting system cleanup"

dnf remove iptables-services \
  iptables-utils \
  rsyslog \
  dracut-config-rescue

# Clean package manager cache
dnf -y autoremove
dnf clean all

# Clean temporary files
rm -rf /tmp/*
rm -rf /var/*
mkdir -p /tmp
mkdir -p /var/tmp && chmod -R 1777 /var/tmp

# Clean /var but preserve cache
#find /var/* -maxdepth 0 -type d \! -name cache -exec rm -fr {} \;
# Clean /var/cache but preserve dnf + rpm-ostree
#find /var/cache/* -maxdepth 0 -type d \! -name dnf \! -name rpm-ostree -exec rm -fr {} \;
# Clean dnf cache
#rm /var/{cache,lib}/dnf /var/lib/rhsm /var/cache/ldconfig -rf 

# Restore and setup directories
mkdir -p /var/tmp
chmod -R 1777 /var/tmp

log "Cleanup completed"