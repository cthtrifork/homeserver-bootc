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

echo "--- egress allowlist: claude user and podman subuid range ---"
as_agent() { sudo -u claude -H "$@"; }
# set -e ignores a failing "! cmd", so negative checks go through this
must_fail() { if "$@" >/dev/null 2>&1; then echo "should have been blocked: $*"; exit 1; fi; }
# allowed: on the list (DNS + SNI pass)
as_agent curl -sS --max-time 20 -o /dev/null https://github.com
as_agent getent hosts github.com >/dev/null
# blocked: not on the list (DNS refused), IP literal (no SNI), other ports, subuid range (host-network containers)
must_fail as_agent getent hosts example.com
must_fail as_agent curl -sS --max-time 10 -o /dev/null https://example.com
must_fail as_agent curl -sS --max-time 10 -o /dev/null https://1.1.1.1
must_fail as_agent curl -sS --max-time 10 -o /dev/null --resolve example.com:443:93.184.216.34 https://example.com
must_fail as_agent timeout 10 bash -c 'exec 3<>/dev/tcp/github.com/22'
must_fail sudo -u '#100000' curl -sS --max-time 10 -o /dev/null https://example.com
# plain HTTP is matched on the Host header (the address is pinned so DNS does not answer first)
[ "$(as_agent curl -s --max-time 10 -o /dev/null -w '%{http_code}' --resolve example.com:80:93.184.216.34 http://example.com)" = "403" ]
# not affected: root (bootc, dnf)
sudo curl -sS --max-time 20 -o /dev/null https://github.com

echo "✅ User testing finished"
