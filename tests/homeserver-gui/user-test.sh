#!/usr/bin/env bash
#set -euo pipefail
set -x

trap 'echo "💥 Error on line $LINENO (exit $?): last cmd: $BASH_COMMAND"' ERR

echo "== User testing =="

WHOAMI=$(whoami)

echo "Running as"
id
echo "$WHOAMI"

echo "== Github CLI =="
echo "GitHub token fingerprint: ${GITHUB_TOKEN:0:7}********"
gh auth status && echo "✅ Github CLI is ready"

getent passwd "$WHOAMI"
grep -n '^caspertdk:' /etc/passwd || echo "NOT in /etc/passwd"
grep -n '^caspertdk:' /usr/lib/passwd 2>/dev/null || true

grep -n '^caspertdk:' /etc/shadow || echo "NOT in /etc/shadow"
grep -n '^caspertdk:' /usr/lib/shadow 2>/dev/null || true


echo "Finished testing"
