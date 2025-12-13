#!/usr/bin/env bash
set -eo pipefail

trap 'echo "💥 Error on line $LINENO (exit $?): last cmd: $BASH_COMMAND"' ERR

echo "== User testing =="

WHOAMI=$(whoami)

echo "Running as"
id
echo "$WHOAMI"

echo "== Github CLI =="
echo "GitHub token fingerprint: ${GITHUB_TOKEN:0:7}********"
gh auth status && echo "✅ Github CLI is ready"


echo "== utilities =="
printf "Display: %s\n" "$DISPLAY"
echo "Copy and paste date:"
date | $HOME/.local/bin/copy
$HOME/.local/bin/pasta

echo "== Github SSH Auth =="
echo "Public key and SHA: "
ssh-keygen -y -f ~/.ssh/id_ed25519 | head -c 80; echo
ssh-keygen -lf ~/.ssh/id_ed25519.pub

echo "Verify PAM authentication with default password"
python3 - <<EOF
import pexpect
child = pexpect.spawn("su $WHOAMI -c 'echo OK'")
child.expect("Password:")
child.sendline("Password")
child.expect(pexpect.EOF)
print(child.before.decode())
EOF

python3 - <<EOF
import pam
p = pam.pam()
print("OK" if p.authenticate("$WHOAMI", "Password") else "FAIL")
EOF

echo "Finished testing"

#ssh_github_auth() {
#  ssh -o IdentitiesOnly=yes \
#	  -i ~/.ssh/id_ed25519 \
#	  -o BatchMode=yes \
#	  -o ConnectTimeout=10 \
#	  -o StrictHostKeyChecking=accept-new \
#	  -T git@github.com
#}

#echo "Trying to authenticate..."
# output=$(ssh_github_auth 2>&1)

# echo "$output"

# if echo "$output" | grep -q "successfully"; then
#   echo "✅ SSH authentication succeeded"
# else
#   echo "❌ SSH authentication failed"
#   exit 1
# fi

