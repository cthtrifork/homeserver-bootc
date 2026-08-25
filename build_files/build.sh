#!/usr/bin/bash
# shellcheck disable=SC1091
set -euo pipefail

trap '[[ $BASH_COMMAND != echo* ]] && [[ $BASH_COMMAND != log* ]] && echo "+ $BASH_COMMAND"' DEBUG

log() {
    echo "=== $* ==="
}

usage() {
    echo "Usage: ${0##*/} </ctx/build_files/base>" >&2
    exit 2
}

[[ $# -eq 1 ]] || usage

dir="$1"

[[ -d "$dir" ]] || {
    echo "Missing directory: $dir" >&2
    exit 2
}
for s in "$dir"/*.sh; do
    bash "$s"
done
