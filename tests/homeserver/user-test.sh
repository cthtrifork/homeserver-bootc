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


echo "== Podman =="
# Rootless
curl --unix-socket $XDG_RUNTIME_DIR/podman/podman.sock http://localhost/_ping
# Rootful
sudo curl --unix-socket /run/podman/podman.sock http://localhost/_ping

echo "== Docker =="
echo "Checking if user is in docker group"
getent group docker || echo "docker group not found"
SOCKET_PATH="/run/user/$(id -u)/podman/podman.sock"
if [[ ! -S "$SOCKET_PATH" ]]; then
  echo "Starting rootless podman socket at $SOCKET_PATH"
  systemctl --user start podman.socket
  for _ in {1..10}; do
    [[ -S "$SOCKET_PATH" ]] && break
    sleep 1
  done
fi
docker run --rm hello-world
echo "✅ Docker is ready"

echo "== Utilities =="
printf "Display: %s\n" "$DISPLAY"
echo "Copy and paste date:"
date | $HOME/.local/bin/copy
$HOME/.local/bin/pasta

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

echo "== user binaries =="
memoryusage

echo "== User testing finished =="
