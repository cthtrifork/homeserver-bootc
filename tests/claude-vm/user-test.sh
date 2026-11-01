#!/usr/bin/env bash
set -eo pipefail

trap 'echo "💥 Error on line $LINENO (exit $?): last cmd: $BASH_COMMAND"' ERR

echo "== User testing (claude-vm) =="
id
sudo -n true

echo "--- no private key for this user ---"
if compgen -G "$HOME/.ssh/id_*" >/dev/null; then
    echo "key found in ~/.ssh"
    exit 1
fi

echo "--- seed helper refuses a private key ---"
if printf -- '-----BEGIN OPENSSH PRIVATE KEY-----' | sudo claude-vm-seed-github-token >/dev/null 2>&1; then
    echo "seed helper accepted a private key"
    exit 1
fi
sudo test ! -e /etc/claude-vm/github-token

echo "--- claude user: python, go, npm, rootless podman ---"
sudo -u claude -H bash -lc '
  set -e
  export XDG_RUNTIME_DIR=/run/user/$(id -u)
  claude --version
  python3 -c "print(\"python ok\")"
  test "$(npm config get prefix)" = "$HOME/.npm-global"
  d=$(mktemp -d) && cd "$d" && go mod init example.com/hello >/dev/null 2>&1
  printf "package main\nimport \"fmt\"\nfunc main() { fmt.Println(\"go ok\") }\n" > main.go
  go run . | grep -x "go ok"
  podman info --format "rootless={{.Host.Security.Rootless}}" | grep -x rootless=true
  podman run --rm quay.io/podman/hello
'

echo "✅ User testing finished"
