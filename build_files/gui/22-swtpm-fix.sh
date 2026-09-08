#!/usr/bin/env bash
set -e

trap '[[ $BASH_COMMAND != echo* ]] && [[ $BASH_COMMAND != log* ]] && echo "+ $BASH_COMMAND"' DEBUG

log() {
    echo "=== $* ==="
}

debug() {
    echo "[DEBUG] $*" >&2
}

log "Fixing swtpm SELinux policy"

semodule -i /usr/share/selinux/packages/swtpm*.pp || true

semanage fcontext -a -t swtpm_exec_t "/usr/bin/swtpm" || true
semanage fcontext -a -t swtpm_exec_t "/usr/bin/swtpm_setup" || true

restorecon -v \
    /usr/bin/swtpm \
    /usr/bin/swtpm_setup

debug "swtpm permissions: $(ls -lZ /usr/bin/swtpm)"
