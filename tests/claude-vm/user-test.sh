#!/usr/bin/env bash
set -eo pipefail

trap 'echo "💥 Error on line $LINENO (exit $?): last cmd: $BASH_COMMAND"' ERR

echo "== User testing (claude-vm) =="

id
sudo -n true
echo "✅ passwordless sudo for admin user"

echo "== No private keys for this user =="
if ls ~/.ssh/id_* 2>/dev/null | grep -v '\.pub$' | grep .; then
    echo "private key found in ~/.ssh"
    exit 1
fi
echo "✅ ~/.ssh holds only authorized_keys"

echo "== Seed helper =="
# bad input is rejected, and nothing is written
if printf -- '-----BEGIN OPENSSH PRIVATE KEY-----' | sudo claude-vm-seed-github-token; then
    echo "seed helper accepted a private key"
    exit 1
fi
sudo test ! -e /etc/claude-vm/github-token
echo "✅ private keys are refused"

echo "== claude user =="
sudo -u claude -H bash -lc 'cd ~/workspace && claude --version && git config --global user.name'
sudo -u claude -H git config --system --get-all credential.https://github.com.helper | grep -q 'gh auth git-credential'
echo "✅ claude user can run claude; git uses gh credential helper"

echo "== User testing finished =="
