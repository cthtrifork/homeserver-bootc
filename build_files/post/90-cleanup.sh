#!/usr/bin/bash
#shellcheck disable=SC2115
set -eou pipefail

trap '[[ $BASH_COMMAND != echo* ]] && [[ $BASH_COMMAND != log* ]] && echo "+ $BASH_COMMAND"' DEBUG

log() {
    echo "=== $* ==="
}

log "Starting system cleanup"

# remove resource heavy packages
dnf -y remove \
    rsyslog \
    dracut-config-rescue \
    at

# Nothing requires these on the installed image (rpm -q --whatrequires), but they are pulled in as weak
# dependencies, and the removal in packages-removed runs before later installs bring them back: a compiler
# toolchain for kernel-devel (gcc and cpp go with it) and clang, plus nvidia firmware (~0.8 GB installed with gcc, cpp and llvm21-libs).
# Matched by name so a missing package does not fail the build and a clang/llvm major bump still matches.
{ rpm -qa --qf '%{NAME}\n' | grep -E '^(kernel-devel|clang[0-9]*-libs|compiler-rt[0-9]*|nvidia-gpu-firmware)$' || true; } | xargs -r dnf -y remove

# Clean package manager cache
dnf -y autoremove
#dnf -y clean all

# Documentation is available online
rm -rf /usr/share/doc

# Disable all COPR repos
for i in /etc/yum.repos.d/_copr:*.repo; do
    if [[ -f "$i" ]]; then
        sed -i 's@enabled=1@enabled=0@g' "$i"
    fi
done

# Clean temporary files
rm -rf /tmp/*
#rm -rf /var/*
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
