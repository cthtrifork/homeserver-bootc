#!/usr/bin/env bash
set -euxo pipefail

# ensure selinux permissions
semanage fcontext -a -t swtpm_exec_t /usr/bin/swtpm
semanage fcontext -a -t swtpm_exec_t /usr/bin/swtpm_setup
restorecon -v /usr/bin/swtpm /usr/bin/swtpm_setup
