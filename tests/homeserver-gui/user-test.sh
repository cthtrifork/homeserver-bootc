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

echo "== System Auth =="
python3 - <<EOF
import pam
p = pam.pam()
print("OK" if p.authenticate("$WHOAMI", "Password") else "FAIL")
EOF

echo "== VS Code: no self-update, no telemetry =="
# the dotfiles sync restores these on every boot (like the Zed update switch)
settings="$HOME/.config/Code/User/settings.json"
python3 -c '
import json, sys
s = json.load(open(sys.argv[1]))
want = {
    "update.mode": "none",
    "telemetry.telemetryLevel": "off",
    "extensions.autoUpdate": False,
    "extensions.autoCheckUpdates": False,
}
bad = {k: s.get(k) for k, v in want.items() if s.get(k) != v}
if bad:
    sys.exit("unexpected VS Code settings: %s" % bad)
' "$settings"
grep -q '"enable-crash-reporter": false' "$HOME/.vscode/argv.json"
echo "✅ VS Code self-update, telemetry and crash reporter are off"
