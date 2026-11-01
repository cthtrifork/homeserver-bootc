#!/usr/bin/env bash
set -eo pipefail

trap 'echo "💥 Error on line $LINENO (exit $?): last cmd: $BASH_COMMAND"' ERR

echo "== System testing (claude-vm) =="
id

echo "--- tools ---"
claude --version
for c in bash python3 pip3 node npm go podman skopeo crane gh git bwrap socat ssh; do
    command -v "$c" >/dev/null || { echo "missing: $c"; exit 1; }
done

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
systemctl cat claude-pinggy.service | grep -q '^DynamicUser=yes'
test -x /usr/bin/claude-vm-ssh-address
grep -q claude-vm-ssh-address /etc/claude-code/CLAUDE.md
# nightly bootc upgrade is staged only (no --apply, so no reboot)
systemctl is-enabled --quiet bootc-fetch-apply-updates.timer
systemctl cat bootc-fetch-apply-updates.service | grep -q 'bootc upgrade --quiet'

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
grep -qx 'github.com' /usr/share/claude-vm/egress/allowlist.txt
grep -qx 'anthropic.com' /usr/share/claude-vm/egress/allowlist.txt
if grep -qx 'example.com' /usr/share/claude-vm/egress/allowlist.txt; then echo 'example.com must not be allowlisted'; exit 1; fi
[ "$(jq '.sandbox.network.allowedDomains | length' /etc/claude-code/managed-settings.json)" = "$(( 2 * $(wc -l </usr/share/claude-vm/egress/allowlist.txt) ))" ]
jq -e '.sandbox.network.allowedDomains | index("github.com") and index("*.github.com")' /etc/claude-code/managed-settings.json >/dev/null
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
jq -e '.permissions.disableBypassPermissionsMode == "disable"
       and .sandbox.enabled and .sandbox.failIfUnavailable
       and (.sandbox.allowUnsandboxedCommands | not)
       and (.sandbox.excludedCommands | index("podman *"))
       and .allowManagedHooksOnly and (.hooks.SessionStart | length > 0)' \
    /etc/claude-code/managed-settings.json >/dev/null
# bubblewrap must start under the service's own hardening
sudo systemd-run --wait --pipe --collect -q -p User=claude \
    -p PrivateTmp=yes -p ProtectSystem=strict -p ProtectControlGroups=yes \
    bwrap --unshare-all --ro-bind / / --dev /dev --proc /proc true

echo "--- users, ssh, home directories ---"
[ "$(id -u claude)" = "1100" ]
if id -nG claude | grep -qw wheel; then
    echo "claude must not be in wheel"
    exit 1
fi
id -nG caspertdk | grep -qw wheel
sshd -T | grep -qx 'passwordauthentication no'
grep -q '^ssh-ed25519 ' /var/home/caspertdk/.ssh/authorized_keys
[ "$(stat -c %U:%a /var/home/claude)" = "claude:700" ]
test -e /var/lib/systemd/linger/claude
timeout 60 bash -c 'until [ -d /run/user/1100 ]; do sleep 1; done'

echo "--- nothing secret baked in ---"
hits="$(find /etc /root /var/home /usr/local -xdev -type f \
    \( -name 'id_rsa' -o -name 'id_dsa' -o -name 'id_ecdsa' -o -name 'id_ed25519' -o -name 'github-token' -o -name '.credentials.json' \) 2>/dev/null || true)"
if [ -n "$hits" ]; then
    echo "unexpected key/token file(s):"
    echo "$hits"
    exit 1
fi
[ "$(stat -c %a /etc/claude-vm)" = "700" ]

echo "✅ System testing finished"
