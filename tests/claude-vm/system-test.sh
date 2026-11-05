#!/usr/bin/env bash
set -eo pipefail

trap 'echo "💥 Error on line $LINENO (exit $?): last cmd: $BASH_COMMAND"' ERR

echo "== System testing (claude-vm) =="
id

echo "--- tools ---"
claude --version
for c in bash python3 pip3 node npm go chromium-browser podman podman-compose skopeo crane gh git jq yq shellcheck shfmt yamllint make hadolint actionlint bwrap socat ssh; do
    command -v "$c" >/dev/null || { echo "missing: $c"; exit 1; }
done

test -d /usr/lib/node_modules/playwright

echo "--- services ---"
# enabled, but idle until the GitHub token is seeded and claude is signed in
systemctl is-enabled --quiet claude-remote-control.service
if systemctl is-active --quiet claude-remote-control.service; then
    echo "claude-remote-control is running but nothing was seeded"
    exit 1
fi
# free Pinggy SSH tunnel is opt-in: present but neither enabled nor running
systemctl cat claude-pinggy.service >/dev/null
if systemctl is-enabled --quiet claude-pinggy.service || systemctl is-active --quiet claude-pinggy.service; then
    echo "claude-pinggy must be opt-in"
    exit 1
fi
[ "$(hostname)" = "claude-vm-bootc" ]
test -x /usr/bin/claude-vm-ssh-address
test -x /usr/bin/claude-vm-egress
test -x /usr/bin/claude-vm-signing-key
# nightly bootc upgrade applies (reboots) when a new image is staged
systemctl is-enabled --quiet bootc-fetch-apply-updates.timer

echo "--- egress gateway ---"
for u in nft proxy dns; do
    unit="claude-vm-egress-$u.service"
    if ! timeout 30 bash -c "until systemctl is-active --quiet $unit; do sleep 1; done"; then
        echo "$unit is not active"
        systemctl status --no-pager "$unit" || true
        journalctl -u "$unit" -b --no-pager -n 40 || true
        journalctl -b --no-pager -g 'avc:' | tail -n 20 || true
        exit 1
    fi
done
# the proxy runs from a bin_t copy of nginx; in the packaged httpd_t domain SELinux denies its upstream connections
test -x /usr/libexec/claude-vm/egress-proxy
proxy_label="$(ps -o label= -C egress-proxy | head -n 1)"
echo "egress-proxy runs as: $proxy_label"
if grep -qF httpd_t <<<"$proxy_label"; then echo "egress-proxy must not run in httpd_t"; exit 1; fi
# resolved's varlink socket (glibc nss-resolve) bypasses the DNS redirect for everyone but root
[ "$(stat -c %a /run/systemd/resolve/io.systemd.Resolve)" = 600 ]
tcp="$(ss -ltnH)"
udp="$(ss -lunH)"
grep -qF '127.0.0.1:8443' <<<"$tcp"
grep -qF '127.0.0.1:8008' <<<"$tcp"
grep -qF '127.0.0.55:53' <<<"$udp"
# capture first: with pipefail, `cmd | grep -q` fails with SIGPIPE (141) when grep exits at the first match
rules="$(sudo nft list table inet claude_egress)"
grep -qF 'meta skuid != @agent_uids' <<<"$rules"
# one allowlist (build_files/claude-vm/egress-allowlist.txt) feeds the gateway and the sandbox's allowedDomains
for f in /usr/share/claude-vm/egress/{allowlist.txt,nginx-allow.map,dnsmasq-servers}; do test -s "$f"; done
claude-vm-egress allowed | grep -qx github.com
requires="$(systemctl show -p Requires --value claude-remote-control.service)"
grep -qF claude-vm-egress-proxy <<<"$requires"

echo "--- staged-update notice ---"
sudo bootc status --format json | jq -e '.status | has("staged")' >/dev/null
sudo /usr/libexec/claude-vm/note-staged-update
test ! -e /run/claude-vm/update-staged   # nothing is staged on a fresh install
sudo install -d /run/claude-vm && sudo touch /run/claude-vm/update-staged
sudo -u claude /usr/libexec/claude-vm/session-start-note | jq -e '.hookSpecificOutput.additionalContext | test("staged")' >/dev/null
sudo rm -f /run/claude-vm/update-staged
[ -z "$(sudo -u claude /usr/libexec/claude-vm/session-start-note)" ]

echo "--- policy and Bash sandbox ---"
# bubblewrap must start under the service's own hardening
sudo systemd-run --wait --pipe --collect -q -p User=claude \
    -p PrivateTmp=yes -p ProtectSystem=strict \
    bwrap --unshare-all --ro-bind / / --dev /dev --proc /proc true

echo "--- users, ssh, home directories ---"
[ "$(id -u claude)" = "1100" ]
if id -nG claude | grep -qw wheel; then
    echo "claude must not be in wheel"
    exit 1
fi
id -nG caspertdk | grep -qw wheel
sshd -T | grep -qx 'passwordauthentication no'
[ "$(stat -c %U:%a /var/home/claude)" = "claude:700" ]
test -e /var/lib/systemd/linger/claude
timeout 60 bash -c 'until [ -d /run/user/1100 ]; do sleep 1; done'
# podman API socket: enabled for every user manager and socket-activated for claude
systemctl --global is-enabled podman.socket
timeout 60 bash -c 'until [ -S /run/user/1100/podman/podman.sock ]; do sleep 1; done'
# ...but it must not be exposed to the sandbox (it would bypass the file rules and podman's approval prompt)
if jq -e '.sandbox.network.allowUnixSockets' /etc/claude-code/managed-settings.json >/dev/null; then
    echo "the podman socket must not be exposed to the sandbox"
    exit 1
fi

echo "--- nothing secret baked in ---"
hits="$(find /etc /root /var/home /usr/local -xdev -type f \
    \( -name 'id_rsa' -o -name 'id_dsa' -o -name 'id_ecdsa' -o -name 'id_ed25519' -o -name 'github-token' -o -name 'private-key.pem' -o -name '.credentials.json' \) 2>/dev/null || true)"
if [ -n "$hits" ]; then
    echo "unexpected key/token file(s):"
    echo "$hits"
    exit 1
fi
[ "$(stat -c %a /etc/claude-vm)" = "700" ]

echo "✅ System testing finished"
