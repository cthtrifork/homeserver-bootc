#!/usr/bin/bash
# shellcheck disable=SC1091

set -euo pipefail

trap '[[ $BASH_COMMAND != echo* ]] && [[ $BASH_COMMAND != log* ]] && echo "+ $BASH_COMMAND"' DEBUG

log() {
  echo "=== $* ==="
}

rsync -rvpK /ctx/system_files/homeserver/ /

mkdir -p /etc/homeserver/metadata/
cat > /etc/homeserver/metadata/pinggy <<EOF
PINGGY_TOKEN=$PINGGY_TOKEN
PINGGY_HOST=$PINGGY_HOST
EOF
chmod 600 /etc/homeserver/metadata/pinggy

/ctx/build_files/github-cli.sh
/ctx/build_files/server-docker-ce.sh
/ctx/build_files/utilities.sh
/ctx/build_files/systemd.sh

log "Build process completed"