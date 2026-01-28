#!/usr/bin/env bash
set -euo pipefail

trap '[[ $BASH_COMMAND != echo* ]] && [[ $BASH_COMMAND != log* ]] && echo "+ $BASH_COMMAND"' DEBUG

log() {
    echo "=== $* ==="
}

debug() {
    echo "[DEBUG] $*" >&2
}

log "Setting default GUI keymap to Danish"
echo "KEYMAP=dk" | tee -a /etc/vconsole.conf
