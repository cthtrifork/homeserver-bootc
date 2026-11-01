#!/usr/bin/env bash
set -eo pipefail

trap 'echo "💥 Error on line $LINENO (exit $?): last cmd: $BASH_COMMAND"' ERR

echo "== System testing (claude-vm) =="

echo "Running as"
id

echo "--- claude binary ---"
claude --version

echo "--- toolchain for Claude: bash, python, node/npm, go, podman ---"
for c in bash python3 pip3 node npm go podman gh git; do
    command -v "$c" >/dev/null || { echo "missing: $c"; exit 1; }
done
bash --version | head -1; python3 --version; pip3 --version; node --version; npm --version; go version; podman --version
grep -qx 'claude:100000:65536' /etc/subuid
echo "✅ toolchain present, subuid configured for claude"

echo "--- service is enabled, and idle until token + login are seeded ---"
systemctl is-enabled --quiet claude-remote-control.service
if systemctl is-active --quiet claude-remote-control.service; then
    echo "claude-remote-control is running but nothing was seeded"
    exit 1
fi
echo "✅ claude-remote-control enabled and idle (conditions unmet, as expected)"

echo "--- bootc update schedule ---"
systemctl is-enabled --quiet bootc-fetch-apply-updates.timer
systemctl cat bootc-fetch-apply-updates.timer | grep -qx 'OnCalendar=\*-\*-\* 00:30:00'
systemctl cat bootc-fetch-apply-updates.service | grep -qx 'ExecStart=/usr/bin/bootc upgrade --quiet'
echo "✅ nightly bootc upgrade is scheduled (staged, no auto-reboot)"

echo "--- managed settings (highest precedence, root-owned) ---"
f=/etc/claude-code/managed-settings.json
jq -e '.permissions.disableBypassPermissionsMode == "disable"' "$f" >/dev/null
[ "$(stat -c %U "$f")" = "root" ]
if sudo -u claude test -w "$f"; then
    echo "claude can modify its own managed settings"
    exit 1
fi
jq -e '.sandbox.enabled == true and .sandbox.failIfUnavailable == true and .sandbox.allowUnsandboxedCommands == false' "$f" >/dev/null
jq -e '.sandbox.excludedCommands | index("podman *")' "$f" >/dev/null
echo "✅ bypass permissions mode disabled, strict Bash sandbox required; claude cannot edit the policy"

echo "--- Bash sandbox can start under the service's own hardening ---"
command -v bwrap >/dev/null && command -v socat >/dev/null
sudo systemd-run --wait --pipe --collect -q -p User=claude \
    -p PrivateTmp=yes -p ProtectSystem=strict -p ProtectControlGroups=yes -p ProtectKernelModules=yes \
    bwrap --unshare-all --ro-bind / / --dev /dev --proc /proc true
echo "✅ bubblewrap can create a sandbox as claude"

echo "--- users ---"
[ "$(id -u claude)" = "1100" ]
if id -nG claude | tr ' ' '\n' | grep -qx wheel; then
    echo "claude must not be in wheel"
    exit 1
fi
id -nG caspertdk | tr ' ' '\n' | grep -qx wheel
echo "✅ claude (1100) is unprivileged, caspertdk is in wheel"

echo "--- tmpfiles: home dirs and lingering for rootless podman ---"
[ "$(stat -c '%U:%a' /var/home/claude)" = "claude:700" ]
[ "$(stat -c %U /var/home/claude/workspace)" = "claude" ]
[ "$(stat -c '%U:%a' /var/home/caspertdk/.ssh)" = "caspertdk:700" ]
[ "$(stat -c '%U:%a' /var/home/caspertdk/.ssh/authorized_keys)" = "caspertdk:600" ]
test -e /var/lib/systemd/linger/claude
timeout 60 bash -c 'until [ -d /run/user/1100 ]; do sleep 1; done'
echo "✅ home dirs, authorized_keys permissions and lingering are in place"

echo "--- ssh ---"
sshd -T | grep -qx 'passwordauthentication no'
grep -q '^ssh-ed25519 ' /var/home/caspertdk/.ssh/authorized_keys
echo "✅ key-only SSH, authorized_keys seeded for caspertdk"

echo "--- no private keys or tokens baked in ---"
if find /etc /root /var/home /usr/local -xdev -type f \
    \( -name 'id_rsa' -o -name 'id_ecdsa' -o -name 'id_ed25519' -o -name 'github-token' -o -name '.credentials.json' \) | grep .; then
    echo "unexpected key/token file present"
    exit 1
fi
if grep -rIlE -e '-----BEGIN [A-Z ]*PRIVATE KEY-----' /etc/claude-vm /var/home 2>/dev/null | grep .; then
    echo "unexpected private key material present"
    exit 1
fi
test -d /etc/claude-vm
[ "$(stat -c %a /etc/claude-vm)" = "700" ]
echo "✅ no private keys; /etc/claude-vm is 0700 and empty until seeded"

echo "== System testing finished =="
