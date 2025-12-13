#!/usr/bin/env bash
set -euo pipefail

trap 'echo "💥 Error on line $LINENO (exit $?): last cmd: $BASH_COMMAND"' ERR

echo "== User testing =="

WHOAMI=$(whoami)

echo "Running as"
id
echo "$WHOAMI"

echo "== Github SSH Auth =="
echo "Public key and SHA: "
ssh-keygen -y -f ~/.ssh/id_ed25519 | head -c 80; echo
ssh-keygen -lf ~/.ssh/id_ed25519.pub

python3 - <<EOF
import pam
p = pam.pam()
print("OK" if p.authenticate("$WHOAMI", "Password") else "FAIL")
EOF