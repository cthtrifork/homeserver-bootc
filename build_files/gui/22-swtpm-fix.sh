#!/usr/bin/env bash
set -euxo pipefail

# Ensure SELinux permissions
semodule -i /usr/share/selinux/packages/swtpm*.pp
restorecon -v /usr/bin/swtpm /usr/bin/swtpm_setup
