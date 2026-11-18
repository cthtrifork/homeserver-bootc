#!/usr/bin/bash
set -euo pipefail

trap '[[ $BASH_COMMAND != echo* ]] && [[ $BASH_COMMAND != log* ]] && echo "+ $BASH_COMMAND"' DEBUG

log() {
    echo "=== $* ==="
}

# The swtpm binaries are written by rpm inside the container build, where SELinux is not applied, so they ship as bin_t.
# /usr is read-only on the host (restorecon fails there), and libvirt then cannot start swtpm for a VM with a TPM:
# "cannot execute binary /usr/bin/swtpm: Permission denied" (AVC: svirt_t entrypoint on bin_t).
# Label them from the policy's file contexts now, and fail the build if the label did not stick.
log "Labelling swtpm binaries"
setfiles -F /etc/selinux/targeted/contexts/files/file_contexts /usr/bin/swtpm*
python3 -c "import os; l = os.getxattr('/usr/bin/swtpm', 'security.selinux'); print(l); assert b'swtpm_exec_t' in l"
