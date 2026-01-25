#!/usr/bin/bash
# shellcheck disable=SC1091
set -euo pipefail

trap '[[ $BASH_COMMAND != echo* ]] && [[ $BASH_COMMAND != log* ]] && echo "+ $BASH_COMMAND"' DEBUG

log() {
    echo "=== $* ==="
}

usage() {
  echo "Usage: ${0##*/} <core|gui>" >&2
  exit 2
}

[[ $# -eq 1 ]] || usage

case "$1" in
  core|gui) VARIANT="$1" ;;
  *) usage ;;
esac

for dir in \
  /ctx/build_files/base \
  "/ctx/build_files/$VARIANT" \
  /ctx/build_files/post
do
  [[ -d "$dir" ]] || { echo "Missing directory: $dir" >&2; exit 2; }
  for s in "$dir"/*.sh; do
    bash "$s"
  done
done