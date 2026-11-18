#!/usr/bin/env bash
set -eo pipefail

# Guards for the claude-vm image: negative checks (things that must NOT be true) and the hardening assertions (permissions,
# ownership, ACLs, firewall rules, SSH config). Split out of system-test.sh, which keeps the "does it work" checks (tools, units,
# files present). Like system-test.sh, it runs as a user with sudo on the VM.

trap 'echo "💥 Error on line $LINENO (exit $?): last cmd: $BASH_COMMAND"' ERR

echo "== Guard testing (claude-vm) =="

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
# the proxy runs from a bin_t copy of nginx; in the packaged httpd_t domain SELinux denies its upstream connections
proxy_label="$(ps -o label= -C egress-proxy | head -n 1)"
echo "egress-proxy runs as: $proxy_label"
if grep -qF httpd_t <<<"$proxy_label"; then echo "egress-proxy must not run in httpd_t"; exit 1; fi
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
# each podman socket is reachable by its own agent only
[ "$(stat -c %U:%G:%a /run/claude-vm-podman/claude/podman.sock)" = "claude-podman:claude:660" ]
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
