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
systemctl --user status podman.socket
loginctl show-user $USER | grep Linger
echo "Docker.shim can use rootless podman:"
curl --silent --unix-socket $XDG_RUNTIME_DIR/podman/podman.sock http://localhost/_ping
echo
echo "Docker.shim can use rootful podman:"
sudo curl  --silent --unix-socket /run/podman/podman.sock http://localhost/_ping
echo
echo "== Docker =="
echo "Checking if user is in docker group"
getent group docker || echo "docker group not found"
echo
echo "Testing docker.shim"
docker run --rm hello-world
echo "Testing docker.real"
DOCKER_HOST="unix:///var/run/docker.sock" docker run --rm hello-world
echo "Testing docker.real as root"
export DOCKER_HOST="unix:///var/run/docker.sock"
sudo -E docker run --rm hello-world
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
print("OK (PAM)" if p.authenticate("$WHOAMI", "Password") else "FAIL (PAM)")
EOF

echo "== user binaries =="
memoryusage

echo "== User testing finished =="
