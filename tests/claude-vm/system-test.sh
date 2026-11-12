#!/usr/bin/env bash
set -eo pipefail

# on failure, also dump the podman units and the socket directories (the VM journal only reaches the run summary)
diagnose() {
    echo "--- podman diagnostics ---"
    systemctl status 'claude-vm-podman@*' --no-pager -l 2>&1 | tail -n 40 || true
    journalctl -b --no-pager -n 40 -u 'claude-vm-podman@*' 2>&1 || true
    ls -laZ /run/claude-vm-podman /run/claude-vm-podman/* /run/claude-vm-podman-run 2>&1 || true
    getfacl -p /var/home/claude /var/home/claude/workspace 2>&1 || true
    journalctl -b --no-pager -g 'avc:' 2>&1 | tail -n 20 || true
}
trap 'echo "💥 Error on line $LINENO (exit $?): last cmd: $BASH_COMMAND"; diagnose' ERR

echo "== System testing (claude-vm) =="
id

echo "--- tools ---"
claude --version
for c in bash python3 pip3 node npm go chromium-browser ffmpeg ffprobe podman podman-compose skopeo crane gh git jq yq shellcheck shfmt yamllint make hadolint actionlint bwrap socat ssh; do
    command -v "$c" >/dev/null || { echo "missing: $c"; exit 1; }
done

test -d /usr/lib/node_modules/playwright

# Node needs the full ICU data (nodejs-full-i18n): without it Intl.Segmenter segfaults instead of throwing.
graphemes="$(node -e 'console.log([...new Intl.Segmenter("en", { granularity: "grapheme" }).segment("héllo 👍🏽")].length)' || true)"
[ "$graphemes" = "7" ] || { echo "node: Intl.Segmenter is broken (got '$graphemes'): is nodejs-full-i18n installed?"; exit 1; }

echo "--- services ---"
# enabled, but idle until the GitHub token is seeded and claude is signed in
systemctl is-enabled --quiet claude-remote-control.service
if systemctl is-active --quiet claude-remote-control.service; then
    echo "claude-remote-control is running but nothing was seeded"
    exit 1
fi
# personal Claude login (own Unix user claude-rc-personal): opt-in, independent of the claude service
systemctl cat claude-remote-control-rc-personal.service >/dev/null
if systemctl is-enabled --quiet claude-remote-control-rc-personal.service || systemctl is-active --quiet claude-remote-control-rc-personal.service; then
    echo "claude-remote-control-rc-personal must be opt-in"
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
# user-level Haiku subagents, linked into each agent account by tmpfiles.d
test -f /usr/share/claude-vm/agents/cluster-ops.md
test -f /usr/share/claude-vm/agents/ci-triage.md
test -f /usr/share/claude-vm/agents/lint-runner.md
test -f /usr/share/claude-vm/agents/researcher.md
# nightly bootc upgrade applies (reboots) when a new image is staged
systemctl is-enabled --quiet bootc-fetch-apply-updates.timer
# the Update VMs poll is enabled; without the DNS record it only logs that the page is unreachable
systemctl is-enabled --quiet claude-vm-upgrade-poll.timer
systemctl cat claude-vm-upgrade-poll.service >/dev/null

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
grep -qF '1100-1101' <<<"$rules"
grep -qF '1200-1201' <<<"$rules"
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

# An agent's home is private: owned by it, no group or other access. claude-vm-podman@<agent> adds a traverse-only ACL entry for
# <agent>-podman, which makes `stat` show the ACL mask in the group bits (0710), so check the ACL, not the mode.
home_private() {
    [ "$(stat -c %U "/var/home/$1")" = "$1" ]
    acl="$(getfacl -cp "/var/home/$1")"
    grep -qx 'group::---' <<<"$acl"
    grep -qx 'other::---' <<<"$acl"
    # the only other entry allowed is the podman user's traverse-only one
    extra="$(grep -E '^(user|group):[^:]+:' <<<"$acl" | grep -vE "^user:$1-podman:--x$" || true)"
    [ -z "$extra" ] || { echo "unexpected ACL entries on /var/home/$1: $extra"; return 1; }
}
echo "--- users, ssh, home directories ---"
[ "$(id -u claude)" = "1100" ]
if id -nG claude | grep -qw wheel; then
    echo "claude must not be in wheel"
    exit 1
fi
[ "$(id -u claude-rc-personal)" = "1101" ]
if id -nG claude-rc-personal | tr ' ' '\n' | grep -qxE 'wheel|claude'; then
    echo "claude-rc-personal must not be in wheel or share claude's group"
    exit 1
fi
home_private claude-rc-personal
test -e /var/lib/systemd/linger/claude-rc-personal
# each agent user has its own GitHub App: the token directories are private, and the refresher is a per-user template
[ "$(stat -c %U:%G:%a /run/claude-vm/claude)" = "root:claude:750" ]
[ "$(stat -c %U:%G:%a /run/claude-vm/claude-rc-personal)" = "root:claude-rc-personal:750" ]
systemctl cat 'claude-vm-github-token@claude-rc-personal.service' 'claude-vm-github-token@claude-rc-personal.timer' >/dev/null
if sudo -u claude-rc-personal test -r /var/home/claude/.claude.json || sudo -u claude-rc-personal test -x /run/claude-vm/claude; then
    echo "claude-rc-personal can read claude's files"
    exit 1
fi
id -nG caspertdk | grep -qw wheel
# not `sshd -T | grep -q`: grep exits at the first match and, under pipefail, sshd's SIGPIPE on the rest of its output fails the pipeline
sshd_config="$(sshd -T)"
# case-insensitive: OpenSSH 10.5 (Fedora 45) prints `PasswordAuthentication no`, older releases printed it lowercase
grep -qix 'passwordauthentication no' <<<"$sshd_config"
home_private claude
test -e /var/lib/systemd/linger/claude
timeout 60 bash -c 'until [ -d /run/user/1100 ]; do sleep 1; done'
# containers run as separate UIDs (claude-vm-podman@<agent>.service), not as the agents
[ "$(id -u claude-podman)" = "1200" ]
[ "$(id -u claude-rc-personal-podman)" = "1201" ]
for pu in claude-podman claude-rc-personal-podman; do
    [ "$(getent passwd "$pu" | cut -d: -f7)" = "/usr/sbin/nologin" ]
    if id -nG "$pu" | tr ' ' '\n' | grep -qxE 'wheel|claude|claude-rc-personal'; then
        echo "$pu must not be in wheel or an agent's group"
        exit 1
    fi
done
# the agent users have no subuid range and cannot exec the real podman; the wrapper (first on PATH) talks to the API instead
if grep -qE '^(claude|claude-rc-personal):' /etc/subuid /etc/subgid; then
    echo "agent users must not have a subuid/subgid range"
    exit 1
fi
[ "$(stat -c %G:%a /usr/bin/podman)" = "claude-podman-exec:750" ]
for u in claude claude-rc-personal; do
    if sudo -u "$u" test -x /usr/bin/podman; then echo "$u can exec /usr/bin/podman"; exit 1; fi
done
test -x /usr/libexec/claude-vm/bin/podman
# each podman socket is reachable by its own agent only
timeout 60 bash -c 'until [ -S /run/claude-vm-podman/claude/podman.sock ]; do sleep 1; done'
[ "$(stat -c %U:%G:%a /run/claude-vm-podman/claude/podman.sock)" = "claude-podman:claude:660" ]
sudo -u claude test -w /run/claude-vm-podman/claude/podman.sock
if sudo -u claude-rc-personal test -x /run/claude-vm-podman/claude; then echo "claude-rc-personal reaches claude's podman socket"; exit 1; fi
# the podman user cannot read the agent's secrets, whatever a container asks for
if sudo -u claude-podman test -r /var/home/claude/.claude/.credentials.json || sudo -u claude-podman test -x /run/claude-vm/claude; then
    echo "claude-podman can reach claude's secrets"
    exit 1
fi
# ...but its workspace is shared by ACL
sudo -u claude-podman test -w /var/home/claude/workspace
# the old per-user podman.socket must be gone; and the socket must still not be exposed to the sandbox
if systemctl --global is-enabled podman.socket 2>/dev/null; then echo "podman.socket must not be enabled for the agent users"; exit 1; fi
if jq -e '.sandbox.network.allowUnixSockets' /etc/claude-code/managed-settings.json >/dev/null; then
    echo "the podman socket must not be exposed to the sandbox"
    exit 1
fi

echo "--- usage telemetry ---"
jq -e '.env.CLAUDE_CODE_ENABLE_TELEMETRY == "1" and .env.OTEL_EXPORTER_OTLP_PROTOCOL == "http/protobuf" and .env.OTEL_METRICS_INCLUDE_SESSION_ID == "false"' /etc/claude-code/managed-settings.json >/dev/null
claude-vm-egress allowed | grep -qx portableinfo.cloud

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
