#!/usr/bin/env bash
set -eo pipefail

# on failure, also dump what the egress gateway did (the VM journal only reaches the run summary)
diagnose() {
    echo "--- egress diagnostics ---"
    sudo journalctl -b --no-pager -n 60 -u claude-vm-egress-proxy -u claude-vm-egress-dns || true
    sudo claude-vm-egress blocked | tail -n 20 || true
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

echo "--- seed helper refuses a non-PEM key and writes nothing ---"
if printf 'not a key' | sudo claude-vm-seed-github-app claude 1 2 >/dev/null 2>&1; then
    echo "seed helper accepted a non-PEM key"
    exit 1
fi
sudo test ! -e /etc/claude-vm/github-app/claude/private-key.pem

echo "--- claude cannot read the App private key ---"
if cat /etc/claude-vm/github-app/claude/private-key.pem >/dev/null 2>&1; then
    echo "claude can read the App private key"
    exit 1
fi

echo "--- claude user: python, go, npm, rootless podman ---"
sudo -u claude -H bash -lc '
  set -e
  export PATH=/usr/libexec/claude-vm/bin:$PATH
  claude --version
  python3 -c "print(\"python ok\")"
  test "$(npm config get prefix)" = "$HOME/.npm-global"
  d=$(mktemp -d) && cd "$d" && go mod init example.com/hello >/dev/null 2>&1
  printf "package main\nimport \"fmt\"\nfunc main() { fmt.Println(\"go ok\") }\n" > main.go
  go run . | grep -x "go ok"
  podman info --format "rootless={{.Host.Security.Rootless}}" | grep -x rootless=true
  podman run --rm mirror.gcr.io/library/hello-world
  # `podman compose` needs a provider; podman-compose is the one the image ships
  podman-compose --version
  podman compose version
'

echo "--- playwright drives headless chromium ---"
# the tests are piped over ssh, so write the script to a temp file the claude user can read
pw_script="$(mktemp --suffix=.js)"
chmod 0644 "$pw_script"
cat >"$pw_script" <<'JS'
const { chromium } = require('playwright');
const fs = require('fs');
const os = require('os');
const path = require('path');
(async () => {
  const browser = await chromium.launch({ executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH, args: ['--no-sandbox'] });
  const page = await browser.newPage();
  await page.goto('data:text/html,<h1 id=x>playwright ok</h1>');
  console.log(await page.textContent('#x'));
  await browser.close();
  // recordVideo needs Playwright's bundled ffmpeg (installed at build time); the context must close to flush the .webm
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'pw-video-'));
  const rec = await chromium.launch({ executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH, args: ['--no-sandbox'] });
  const ctx = await rec.newContext({ recordVideo: { dir, size: { width: 320, height: 200 } } });
  const vpage = await ctx.newPage();
  await vpage.goto('data:text/html,<h1>video</h1>');
  await vpage.waitForTimeout(500);
  await ctx.close();
  await rec.close();
  const webm = fs.readdirSync(dir).filter((f) => f.endsWith('.webm'));
  if (webm.length !== 1 || fs.statSync(path.join(dir, webm[0])).size === 0) throw new Error('no .webm recorded in ' + dir);
  const codec = require('child_process').execFileSync('ffprobe', ['-v', 'error', '-select_streams', 'v:0', '-show_entries', 'stream=codec_name', '-of', 'csv=p=0', path.join(dir, webm[0])]).toString().trim();
  fs.rmSync(dir, { recursive: true });
  if (codec !== 'vp9') throw new Error('expected a vp9 .webm, got ' + codec);
  console.log('video ok (' + codec + ')');
})().catch((e) => { console.error(e); process.exit(1); });
JS
pw_out="$(sudo -u claude -H bash -lc "cd / && node $pw_script")"
echo "$pw_out"
grep -x "playwright ok" <<<"$pw_out"
grep -x "video ok (vp9)" <<<"$pw_out"
rm -f "$pw_script"

echo "--- podman API socket answers (outside the sandbox) ---"
sudo -u claude -H curl -sf --unix-socket /run/claude-vm-podman/claude/podman.sock http://d/_ping | grep -x OK

echo "--- containers cannot reach the agent's secrets (separate UID) ---"
# the agent's podman is the wrapper; flags that would defeat SELinux or file permissions in a same-UID podman do nothing here
agent_podman() { (cd / && sudo -u claude -H env PATH=/usr/libexec/claude-vm/bin:/usr/bin podman "$@"); }
img_s=mirror.gcr.io/library/alpine:latest
agent_podman pull -q "$img_s" >/dev/null
secret_blocked() {
    local out
    if out="$(agent_podman run --rm --pull=never "$@" "$img_s" cat /x/podman-test-secret 2>&1)"; then echo "container read the secret file: $*"; echo "$out"; exit 1; fi
}
# a stand-in for .credentials.json (the real one is not present in the test VM)
sudo -u claude sh -c "echo secret > /var/home/claude/.claude/podman-test-secret && chmod 0600 /var/home/claude/.claude/podman-test-secret"
secret_blocked -v /var/home/claude/.claude:/x
secret_blocked -v /var/home/claude/.claude:/x:Z
secret_blocked -v /var/home/claude/.claude:/x:z
secret_blocked --security-opt label=disable -v /var/home/claude/.claude:/x
secret_blocked --privileged -v /var/home/claude/.claude:/x
secret_blocked --userns=host -v /var/home/claude/.claude:/x
secret_blocked --user 0:0 -v /var/home/claude/.claude:/x
# a symlink in the workspace pointing at the secrets does not help either
sudo -u claude ln -sfn /var/home/claude/.claude /var/home/claude/workspace/secret-link
secret_blocked -v /var/home/claude/workspace/secret-link:/x
sudo -u claude rm -f /var/home/claude/workspace/secret-link /var/home/claude/.claude/podman-test-secret
# the signing key and the token are out of reach as well
if agent_podman run --rm --pull=never --privileged -v /var/home/claude/.ssh:/x "$img_s" ls /x >/dev/null 2>&1; then echo "container listed ~/.ssh"; exit 1; fi
if agent_podman run --rm --pull=never --privileged -v /run/claude-vm/claude:/x "$img_s" ls /x >/dev/null 2>&1; then echo "container listed the token directory"; exit 1; fi

echo "--- containers read and write the workspace; the agent can use what they write ---"
ws=/var/home/claude/workspace/podman-acl-test
sudo -u claude install -d "$ws"
sudo -u claude sh -c "echo from-agent > $ws/in.txt"
agent_podman run --rm --pull=never -v "$ws":/w "$img_s" sh -c 'grep -x from-agent /w/in.txt && echo from-container > /w/out.txt'
sudo -u claude grep -x from-container "$ws/out.txt"
sudo -u claude sh -c "echo edited >> $ws/out.txt && rm -rf $ws"
# the other agent's containers cannot touch claude's workspace
if sudo -u claude-rc-personal-podman test -r /var/home/claude/workspace; then echo "claude-rc-personal-podman reads claude's workspace"; exit 1; fi
# direct podman is not an option for the agent
if sudo -u claude -H /usr/bin/podman info >/dev/null 2>&1; then echo "claude ran /usr/bin/podman"; exit 1; fi

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
# blocked requests are logged to the journal; check the claude-vm-egress summary (one "count time scheme host" line per host)
for _ in $(seq 30); do blocked="$(sudo claude-vm-egress blocked)"; grep -qE ' http example\.com$' <<<"$blocked" && break; sleep 1; done
echo "--- claude-vm-egress blocked ---"
echo "$blocked"
grep -qE '^[0-9]+ [^ ]+ https example\.com$' <<<"$blocked" || { echo "no https entry in the blocked summary"; diagnose; exit 1; }
grep -qE '^[0-9]+ [^ ]+ http example\.com$' <<<"$blocked" || { echo "no http entry in the blocked summary"; diagnose; exit 1; }
# one line per host, and allowed requests are not logged
[ -z "$(sort <<<"$blocked" | cut -d' ' -f3- | uniq -d)" ]
if grep -qF 'github.com' <<<"$blocked"; then echo "allowed github.com was logged as blocked"; exit 1; fi
# the allowlist listing agrees with what was just allowed and blocked
echo "--- claude-vm-egress allowed (first 5) ---"
allowed="$(claude-vm-egress allowed)"
echo "$allowed" | head -n 5
grep -qx github.com <<<"$allowed"
if grep -qx example.com <<<"$allowed"; then echo "example.com must not be allowed"; exit 1; fi
# not affected: root (bootc, dnf)
sudo curl -sS --max-time 20 -o /dev/null https://github.com

echo "--- egress allowlist: podman containers ---"
img=mirror.gcr.io/curlimages/curl:latest   # the curl project's image via Google's Docker Hub mirror (~12 MB); gcr.io is allowlisted
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
