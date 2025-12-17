#!/usr/bin/bash
# shellcheck disable=SC1091

set -euo pipefail

trap '[[ $BASH_COMMAND != echo* ]] && [[ $BASH_COMMAND != log* ]] && echo "+ $BASH_COMMAND"' DEBUG

log() {
  echo "=== $* ==="
}

mkdir -p /etc/homeserver/metadata/
cat > /etc/homeserver/metadata/pinggy <<EOF
PINGGY_TOKEN=$PINGGY_TOKEN
PINGGY_HOST=$PINGGY_HOST
EOF
chmod 600 /etc/homeserver/metadata/pinggy

/ctx/build_files/server-docker-ce.sh
/ctx/build_files/systemd.sh
/ctx/build_files/cleanup.sh

log "Build process completed"