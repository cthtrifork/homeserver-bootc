#!/usr/bin/env bash
set -eo pipefail

# on failure, also dump what the egress gateway did (the VM journal only reaches the run summary)
diagnose() {
    echo "--- egress diagnostics ---"
    sudo journalctl -b --no-pager -n 60 -u claude-vm-egress-proxy -u claude-vm-egress-dns || true
    sudo journalctl -b --no-pager -t egress_blocked | tail -n 20 || true
    sudo journalctl -b --no-pager -g 'avc:' | tail -n 20 || true
    sudo nft list table inet claude_egress || true
}
trap 'echo "💥 Error on line $LINENO (exit $?): last cmd: $BASH_COMMAND"; diagnose' ERR

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
  podman run --rm docker.io/library/hello-world
'

echo "--- playwright drives headless chromium ---"
# the tests are piped over ssh, so write the script to a temp file the claude user can read
pw_script="$(mktemp --suffix=.js)"
chmod 0644 "$pw_script"
cat >"$pw_script" <<'JS'
const { chromium } = require('playwright');
(async () => {
  const browser = await chromium.launch({ executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH, args: ['--no-sandbox'] });
  const page = await browser.newPage();
  await page.goto('data:text/html,<h1 id=x>playwright ok</h1>');
  console.log(await page.textContent('#x'));
  await browser.close();
})().catch((e) => { console.error(e); process.exit(1); });
JS
sudo -u claude -H bash -lc "cd / && node $pw_script" | grep -x "playwright ok"
rm -f "$pw_script"

echo "--- podman API socket answers (outside the sandbox) ---"
sudo -u claude -H env XDG_RUNTIME_DIR=/run/user/1100 curl -sf --unix-socket /run/user/1100/podman/podman.sock http://d/_ping | grep -x OK

echo "--- claude doctor reports no invalid settings ---"
# doctor exits 0 even when a settings file is invalid, so look for its "Invalid settings" section
doctor_out="$(sudo -u claude -H bash -lc 'cd ~ && timeout 60 claude doctor </dev/null' 2>&1)"
echo "$doctor_out"
if grep -q '^Invalid settings' <<<"$doctor_out"; then echo "claude doctor found invalid settings"; exit 1; fi

echo "--- egress allowlist: claude user and podman subuid range ---"
as_agent() { sudo -u claude -H "$@"; }
# set -e ignores a failing "! cmd", so negative checks go through this
must_fail() { if "$@" >/dev/null 2>&1; then echo "should have been blocked: $*"; diagnose; exit 1; fi; }
# raw UDP DNS query as claude to the stub resolver in /etc/resolv.conf; prints the response code (0 ok, 5 refused)
dns_rcode() {
    as_agent python3 - "$1" <<'PY'
import socket, struct, sys
name = sys.argv[1]
query = struct.pack(">HHHHHH", 1, 0x0100, 1, 0, 0, 0) + b"".join(bytes([len(p)]) + p.encode() for p in name.split(".")) + b"\0\0\1\0\1"
sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.settimeout(5)
sock.sendto(query, ("127.0.0.53", 53))
print(sock.recv(512)[3] & 15)
PY
}
# allowed: on the list (DNS + SNI pass)
as_agent curl -sS --max-time 20 -o /dev/null https://github.com
as_agent getent hosts github.com >/dev/null
# the DNS filter itself: a listed name is answered, anything else is refused (rcode 5)
[ "$(dns_rcode github.com)" = 0 ]
[ "$(dns_rcode example.com)" = 5 ]
# blocked: not on the list (DNS refused), IP literal (no SNI), other ports, subuid range (host-network containers)
must_fail as_agent getent hosts example.com
must_fail as_agent curl -sS --max-time 10 -o /dev/null https://example.com
must_fail as_agent curl -sS --max-time 10 -o /dev/null https://1.1.1.1
must_fail as_agent curl -sS --max-time 10 -o /dev/null --resolve example.com:443:93.184.216.34 https://example.com
must_fail as_agent timeout 10 bash -c 'exec 3<>/dev/tcp/github.com/22'
must_fail sudo -u '#100000' curl -sS --max-time 10 -o /dev/null https://example.com
# plain HTTP is matched on the Host header (the address is pinned so DNS does not answer first)
[ "$(as_agent curl -s --max-time 10 -o /dev/null -w '%{http_code}' --resolve example.com:80:93.184.216.34 http://example.com)" = "403" ]
# blocked requests are logged to the journal (both the SNI and the Host paths ran above)
blocked_log() { sudo journalctl -b --no-pager -t egress_blocked; }
for _ in $(seq 30); do blocked_log | grep -qF 'http example.com' && break; sleep 1; done
blocked_log | grep -qF 'https example.com' || { echo "no https entry in the blocked log"; diagnose; exit 1; }
# allowed requests are not logged
if blocked_log | grep -qF 'github.com'; then echo "allowed github.com was logged as blocked"; exit 1; fi
# not affected: root (bootc, dnf)
sudo curl -sS --max-time 20 -o /dev/null https://github.com

echo "--- egress allowlist: podman containers ---"
img=docker.io/curlimages/curl:latest   # the curl project's image on Docker Hub (~12 MB); docker.io and docker.com (its CDN) are allowlisted
# from /: podman keeps the caller's cwd, which is caspertdk's home and not enterable by claude
agent_podman() { (cd / && sudo -u claude -H env XDG_RUNTIME_DIR=/run/user/1100 podman "$@"); }
# the container must start and curl must fail: podman's own errors (125-127) do not count as "blocked"
container_blocked() {
    local rc=0
    agent_podman run --rm --pull=never "$@" >/dev/null 2>&1 || rc=$?
    if [ "$rc" -eq 0 ] || [ "$rc" -ge 125 ]; then echo "expected curl in the container to fail (exit $rc): $*"; exit 1; fi
}
agent_podman pull -q "$img" >/dev/null
agent_podman run --rm --pull=never "$img" curl --version >/dev/null
# allowed host works from the default (pasta) network and from the host network
agent_podman run --rm --pull=never "$img" curl -sS --max-time 20 -o /dev/null https://github.com
agent_podman run --rm --pull=never --network=host "$img" curl -sS --max-time 20 -o /dev/null https://github.com
# not on the list: refused name, IP literal, and host-network containers (also as a non-root user, i.e. a subuid)
container_blocked "$img" curl -sS --max-time 10 -o /dev/null https://example.com
container_blocked "$img" curl -sS --max-time 10 -o /dev/null https://1.1.1.1
container_blocked --network=host "$img" curl -sS --max-time 10 -o /dev/null https://example.com
container_blocked --network=host --user 1000:1000 "$img" curl -sS --max-time 10 -o /dev/null https://example.com
container_blocked --network=host --user 1000:1000 "$img" curl -sS --max-time 10 -o /dev/null https://1.1.1.1
# plain HTTP to a name that is not on the list is answered with 403 by the proxy (address pinned so DNS does not refuse first)
[ "$(agent_podman run --rm --pull=never "$img" curl -s --max-time 10 -o /dev/null -w '%{http_code}' --resolve example.com:80:93.184.216.34 http://example.com)" = "403" ]

echo "✅ User testing finished"
