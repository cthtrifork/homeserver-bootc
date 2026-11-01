#!/usr/bin/env bash
set -eo pipefail

trap 'echo "💥 Error on line $LINENO (exit $?): last cmd: $BASH_COMMAND"' ERR

echo "== System testing (claude-vm) =="

echo "Running as"
id

echo "--- claude binary ---"
claude --version

echo "--- service is enabled, and idle until token + login are seeded ---"
systemctl is-enabled --quiet claude-remote-control.service
if systemctl is-active --quiet claude-remote-control.service; then
    echo "claude-remote-control is running but nothing was seeded"
    exit 1
fi
echo "✅ claude-remote-control enabled and idle (conditions unmet, as expected)"

echo "--- users ---"
[ "$(id -u claude)" = "1100" ]
if id -nG claude | tr ' ' '\n' | grep -qx wheel; then
    echo "claude must not be in wheel"
    exit 1
fi
id -nG caspertdk | tr ' ' '\n' | grep -qx wheel
echo "✅ claude (1100) is unprivileged, caspertdk is in wheel"

echo "--- ssh ---"
sshd -T | grep -qx 'passwordauthentication no'
grep -q '^ssh-ed25519 ' /var/home/caspertdk/.ssh/authorized_keys
echo "✅ key-only SSH, authorized_keys seeded for caspertdk"

echo "--- no private keys or tokens baked in ---"
if find /etc /root /var/home /usr/local -xdev -type f \
    \( -name 'id_rsa' -o -name 'id_ecdsa' -o -name 'id_ed25519' -o -name 'github-token' -o -name '.credentials.json' \) | grep .; then
    echo "unexpected key/token file present"
    exit 1
fi
if grep -rIlE -e '-----BEGIN [A-Z ]*PRIVATE KEY-----' /etc/claude-vm /var/home 2>/dev/null | grep .; then
    echo "unexpected private key material present"
    exit 1
fi
test -d /etc/claude-vm
[ "$(stat -c %a /etc/claude-vm)" = "700" ]
echo "✅ no private keys; /etc/claude-vm is 0700 and empty until seeded"

echo "== System testing finished =="
