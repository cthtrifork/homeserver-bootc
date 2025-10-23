#!/usr/bin/env bash
set -euo pipefail

echo "Running as"
id

echo "== Github CLI =="
echo "GitHub token fingerprint: ${GITHUB_TOKEN:0:7}********"
gh auth status && echo "✅ Github CLI is ready"

echo "== Github SSH Auth =="
echo "Public key and SHA: "
ssh-keygen -y -f ~/.ssh/id_ed25519 | head -c 80; echo
ssh-keygen -lf ~/.ssh/id_ed25519.pub
echo "Trying to authenticate..."

set +e
output=$(ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -vT git@github.com 2>&1)
ssh_status=$?
set -e
echo "$output"

if echo "$output" | grep -q "successfully"; then
  echo "✅ SSH authentication succeeded"
else
  echo "❌ SSH authentication failed"
  exit 1
fi
