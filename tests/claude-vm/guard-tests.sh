#!/usr/bin/env bash
set -eo pipefail

# Guards check that the claude-vm image is configured as intended and in the right state: packages and files present, units
# enabled or idle, users, permissions, ACLs, firewall rules, SSH and sandbox config, and what must NOT be true. system-test.sh does
# things and sees that they work. Like system-test.sh, it runs as a user with sudo on the VM.

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

echo "== Guard testing (claude-vm) =="

echo "--- installed ---"
test -d /usr/lib/node_modules/playwright
test -x /usr/libexec/claude-vm/bin/claude-vm-dnf

echo "--- signature policy ---"
# our OS images must be signed by the key in the image (docs/signing.md); other images are not covered here
jq -e '.transports.docker["ghcr.io/cthtrifork/homeserver-bootc"][0] | .type == "sigstoreSigned" and .keyPath == "/etc/pki/cosign/cosign.pub" and .signedIdentity.type == "matchRepository"' /etc/containers/policy.json >/dev/null \
    || { echo "no signature requirement for ghcr.io/cthtrifork/homeserver-bootc in /etc/containers/policy.json"; exit 1; }
grep -q 'BEGIN PUBLIC KEY' /etc/pki/cosign/cosign.pub
grep -q 'use-sigstore-attachments: true' /etc/containers/registries.d/ghcr.yaml

echo "--- units and files ---"
# claude-remote-control is enabled, but idle until the GitHub token is seeded and claude is signed in
systemctl is-enabled --quiet claude-remote-control.service
systemctl cat claude-remote-control-rc-personal.service >/dev/null
systemctl cat claude-pinggy.service >/dev/null
[ "$(hostname)" = "claude-vm-bootc" ]
test -x /usr/bin/claude-vm-ssh-address
test -x /usr/bin/claude-vm-egress
test -x /usr/bin/claude-vm-signing-key
# user-level Haiku subagents, linked into each agent account by tmpfiles.d
test -f /usr/share/claude-vm/agents/cluster-ops.md
test -f /usr/share/claude-vm/agents/ci-triage.md
test -f /usr/share/claude-vm/agents/lint-runner.md
test -f /usr/share/claude-vm/agents/researcher.md
# user-level skills, linked the same way
test -f /usr/share/claude-vm/skills/urlshare/SKILL.md
# nightly bootc upgrade applies (reboots) when a new image is staged
systemctl is-enabled --quiet bootc-fetch-apply-updates.timer
# the 30-minute check stages new images without rebooting
systemctl is-enabled --quiet claude-vm-upgrade-check.timer
systemctl cat claude-vm-upgrade-check.service >/dev/null
# the Update VMs poll is enabled; without the DNS record it only logs that the page is unreachable
systemctl is-enabled --quiet claude-vm-upgrade-poll.timer
systemctl cat claude-vm-upgrade-poll.service >/dev/null
# each agent user has its own GitHub App; the refresher is a per-user template
systemctl cat 'claude-vm-github-token@claude-rc-personal.service' 'claude-vm-github-token@claude-rc-personal.timer' >/dev/null
jq -e '.env.CLAUDE_CODE_ENABLE_TELEMETRY == "1" and .env.OTEL_EXPORTER_OTLP_PROTOCOL == "http/protobuf" and .env.OTEL_METRICS_INCLUDE_SESSION_ID == "false"' /etc/claude-code/managed-settings.json >/dev/null

echo "--- services are opt-in or idle ---"
# claude-remote-control is enabled, but idle until the GitHub token is seeded and claude is signed in
if systemctl is-active --quiet claude-remote-control.service; then
    echo "claude-remote-control is running but nothing was seeded"
    exit 1
fi
# personal Claude login (own Unix user claude-rc-personal): opt-in, independent of the claude service
if systemctl is-enabled --quiet claude-remote-control-rc-personal.service || systemctl is-active --quiet claude-remote-control-rc-personal.service; then
    echo "claude-remote-control-rc-personal must be opt-in"
    exit 1
fi
# free Pinggy SSH tunnel is opt-in: present but neither enabled nor running
if systemctl is-enabled --quiet claude-pinggy.service || systemctl is-active --quiet claude-pinggy.service; then
    echo "claude-pinggy must be opt-in"
    exit 1
fi

echo "--- egress gateway ---"
# the gateway units, listeners, allowlist files and the proxy's SELinux domain are checked next to the allowlist query in system-test.sh
# resolved's varlink socket (glibc nss-resolve) bypasses the DNS redirect for everyone but root
[ "$(stat -c %a /run/systemd/resolve/io.systemd.Resolve)" = 600 ]
# capture first: with pipefail, `cmd | grep -q` fails with SIGPIPE (141) when grep exits at the first match
rules="$(sudo nft list table inet claude_egress)"
grep -qF 'meta skuid != @agent_uids' <<<"$rules"
grep -qF '1100-1101' <<<"$rules"
grep -qF '1200-1201' <<<"$rules"
# the agent cannot run without the egress proxy
requires="$(systemctl show -p Requires --value claude-remote-control.service)"
grep -qF claude-vm-egress-proxy <<<"$requires"

echo "--- users and home directories ---"
# An agent's home is private: owned by it, no group or other access. claude-vm-podman@<agent> adds a traverse-only ACL entry for
# <agent>-podman, which makes `stat` show the ACL mask in the group bits (0710), so check the ACL, not the mode; that is also the
# only extra entry allowed.
home_private() {
    [ "$(stat -c %U "/var/home/$1")" = "$1" ]
    acl="$(getfacl -cp "/var/home/$1")"
    grep -qx 'group::---' <<<"$acl"
    grep -qx 'other::---' <<<"$acl"
    extra="$(grep -E '^(user|group):[^:]+:' <<<"$acl" | grep -vE "^user:$1-podman:--x$" || true)"
    [ -z "$extra" ] || { echo "unexpected ACL entries on /var/home/$1: $extra"; return 1; }
}
home_private claude-rc-personal
home_private claude
[ "$(id -u claude)" = "1100" ]
[ "$(id -u claude-rc-personal)" = "1101" ]
test -e /var/lib/systemd/linger/claude
test -e /var/lib/systemd/linger/claude-rc-personal
timeout 60 bash -c 'until [ -d /run/user/1100 ]; do sleep 1; done'
if id -nG claude | grep -qw wheel; then
    echo "claude must not be in wheel"
    exit 1
fi
if id -nG claude-rc-personal | tr ' ' '\n' | grep -qxE 'wheel|claude'; then
    echo "claude-rc-personal must not be in wheel or share claude's group"
    exit 1
fi
if sudo -u claude-rc-personal test -r /var/home/claude/.claude.json || sudo -u claude-rc-personal test -x /run/claude-vm/claude; then
    echo "claude-rc-personal can read claude's files"
    exit 1
fi
# each agent user has its own GitHub App: the token directories are private
[ "$(stat -c %U:%G:%a /run/claude-vm/claude)" = "root:claude:750" ]
[ "$(stat -c %U:%G:%a /run/claude-vm/claude-rc-personal)" = "root:claude-rc-personal:750" ]
[ "$(stat -c %a /etc/claude-vm)" = "700" ]

echo "--- ssh ---"
id -nG caspertdk | grep -qw wheel
# not `sshd -T | grep -q`: grep exits at the first match and, under pipefail, sshd's SIGPIPE on the rest of its output fails the pipeline
sshd_config="$(sshd -T)"
# case-insensitive: OpenSSH 10.5 (Fedora 45) prints `PasswordAuthentication no`, older releases printed it lowercase
grep -qix 'passwordauthentication no' <<<"$sshd_config"

echo "--- podman isolation ---"
# containers run as separate UIDs (claude-vm-podman@<agent>.service), not as the agents
[ "$(id -u claude-podman)" = "1200" ]
[ "$(id -u claude-rc-personal-podman)" = "1201" ]
for pu in claude-podman claude-rc-personal-podman; do
    if id -nG "$pu" | tr ' ' '\n' | grep -qxE 'wheel|claude|claude-rc-personal'; then
        echo "$pu must not be in wheel or an agent's group"
        exit 1
    fi
done
for pu in claude-podman claude-rc-personal-podman; do
    [ "$(getent passwd "$pu" | cut -d: -f7)" = "/usr/sbin/nologin" ]
done
[ "$(stat -c %G:%a /usr/bin/podman)" = "claude-podman-exec:750" ]
# each podman socket is reachable by its own agent only (its owner and mode are checked next to the socket use in system-test.sh)
# the agent users have no subuid range and cannot exec the real podman; the wrapper talks to the API instead
if grep -qE '^(claude|claude-rc-personal):' /etc/subuid /etc/subgid; then
    echo "agent users must not have a subuid/subgid range"
    exit 1
fi
for u in claude claude-rc-personal; do
    if sudo -u "$u" test -x /usr/bin/podman; then echo "$u can exec /usr/bin/podman"; exit 1; fi
done
if sudo -u claude-rc-personal test -x /run/claude-vm-podman/claude; then echo "claude-rc-personal reaches claude's podman socket"; exit 1; fi
# the podman user cannot read the agent's secrets, whatever a container asks for
if sudo -u claude-podman test -r /var/home/claude/.claude/.credentials.json || sudo -u claude-podman test -x /run/claude-vm/claude; then
    echo "claude-podman can reach claude's secrets"
    exit 1
fi
# the old per-user podman.socket must be gone; and the socket must still not be exposed to the sandbox
if systemctl --global is-enabled podman.socket 2>/dev/null; then echo "podman.socket must not be enabled for the agent users"; exit 1; fi
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

echo "✅ Guard testing finished"
