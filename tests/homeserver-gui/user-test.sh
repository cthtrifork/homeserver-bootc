#!/usr/bin/env bash
set -euo pipefail

trap 'echo "💥 Error on line $LINENO (exit $?): last cmd: $BASH_COMMAND"' ERR

echo "== User testing =="

WHOAMI=$(whoami)

echo "Running as"
id
echo "$WHOAMI"
