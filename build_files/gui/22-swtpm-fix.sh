#!/usr/bin/env bash
set -euxo pipefail

trap '[[ $BASH_COMMAND != echo* ]] && [[ $BASH_COMMAND != log* ]] && echo "+ $BASH_COMMAND"' DEBUG

echo "::group:: ===$(basename "$0")==="

rm -rf /etc/selinux/targeted/tmp /etc/selinux/targeted/previous

semodule -i /usr/share/selinux/packages/swtpm*.pp

restorecon -v \
  /usr/bin/swtpm \
  /usr/bin/swtpm_setup

ls -lZ /usr/bin/swtpm
