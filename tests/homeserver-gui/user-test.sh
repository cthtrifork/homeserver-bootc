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

echo "== utilities =="
printf "Display: %s\n" "$DISPLAY"
echo "Copy and paste date:"
date | $HOME/.local/bin/copy
$HOME/.local/bin/pasta

echo "== Github SSH Auth =="
echo "Public key and SHA: "
ssh-keygen -y -f ~/.ssh/id_ed25519 | head -c 80; echo
ssh-keygen -lf ~/.ssh/id_ed25519.pub

echo "== "$WHOAMI" location =="
grep -E '^(passwd|shadow|group):' /etc/nsswitch.conf

getent passwd "$WHOAMI"
grep -n '^caspertdk:' /etc/passwd || echo "NOT in /etc/passwd"
grep -n '^caspertdk:' /usr/lib/passwd 2>/dev/null || true

grep -n '^caspertdk:' /etc/shadow || echo "NOT in /etc/shadow"
grep -n '^caspertdk:' /usr/lib/shadow 2>/dev/null || true

echo "Verify PAM authentication with default password"
python3 - <<EOF
import pexpect
child = pexpect.spawn("su $WHOAMI -c 'echo OK'")
child.expect("Password:")
child.sendline("Password")
child.expect(pexpect.EOF)
print(child.before.decode())
EOF

python3 - <<'EOF'
import pam
p = pam.pam()
print("OK" if p.authenticate("caspertdk", "Password") else "FAIL")
EOF

echo "== authselect current =="
grep -E '^(passwd|shadow|group):' /etc/nsswitch.conf
authselect current
getent passwd caspertdk
getent -s files passwd caspertdk

getent -s files passwd root || echo "FILES backend broken"
ls -l /etc/passwd
wc -l /etc/passwd

echo "Finished testing"
