#!/usr/bin/bash
# shellcheck disable=SC1091

set -euo pipefail

trap '[[ $BASH_COMMAND != echo* ]] && [[ $BASH_COMMAND != log* ]] && echo "+ $BASH_COMMAND"' DEBUG

log() {
    echo "=== $* ==="
}

#todo look at variant to get the right dirs

for dir in /ctx/build_files/base /ctx/build_files/$variant /ctx/build_files/post; do
    for s in "$dir"/*.sh; do 
        [ -f "$s" ] && "$s";
    done;
done