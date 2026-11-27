#!/usr/bin/env bash
set -eo pipefail

trap 'echo "💥 Error on line $LINENO (exit $?): last cmd: $BASH_COMMAND"' ERR

echo "== System testing =="

echo "Running as"
id

echo "Verifying status for custom installed services..."
CORE_SERVICES="bootc-system-setup" # todo: make dynamic
echo "--- core services ---"
for s in $CORE_SERVICES; do
    systemctl is-active --quiet "$s" || {
        echo "Service not active: $s"
        systemctl status "$s" --no-pager || true
        exit 1
    }
done
echo "✅ core services are OK"

if systemctl is-enabled --quiet vm-upgrade-poll.timer; then
    echo "vm-upgrade-poll.timer must be disabled on the GUI image"
    exit 1
fi
echo "✅ vm-upgrade-poll.timer is disabled"

# rootless podman needs privileged newuidmap/newgidmap; the booted image (not just the build) must still have them
for f in /usr/bin/newuidmap /usr/bin/newgidmap; do
    [[ "$(stat -c '%u:%g %a' "$f")" == "0:0 4755" ]] || {
        echo "$f must be root:root 4755, got: $(stat -c '%U:%G %a' "$f")"
        exit 1
    }
done
echo "✅ newuidmap/newgidmap are setuid root"

# check if env var ENV_LOAD is loaded
if [ -z "${ENV_LOAD:-}" ]; then
    echo "ENV_LOAD is not set"
    exit 1
fi
echo "✅ ENV_LOAD is set to '$ENV_LOAD'. /etc/profile.d/* is working as intended."

echo "--- boot timing ---"
# wait for startup to finish so systemd-analyze reports final numbers; informational only, never fails the test
timeout 120 systemctl is-system-running --wait || true
systemd-analyze time || true
systemd-analyze critical-chain --no-pager || true
echo "--- 15 slowest units ---"
systemd-analyze blame --no-pager | head -15 || true
echo "--- failed units ---"
systemctl --failed --no-pager || true
echo "--- user-setup hook timings ---"
sudo -n journalctl -u 'bootc-user-setup@*' -o short-precise --no-pager 2>&1 | grep -E "user-setup:|Finished|Failed" | tail -20 || true

echo "--- vscode extensions come with the image ---"
grep -qx 'VSCODE_EXTENSIONS=/usr/share/vscode-extensions' /etc/environment.d/50-vscode.conf
count=$(sudo -n -H -u caspertdk env VSCODE_EXTENSIONS=/usr/share/vscode-extensions code --list-extensions 2>/dev/null | grep -c . || true)
echo "extensions code finds in the image directory: $count"
[ "$count" -gt 0 ] || {
    echo "expected extensions installed in the image, found none"
    exit 1
}

echo "--- signature policy ---"
# our OS images must be signed by the key in the image (docs/signing.md); other images are not covered here
jq -e '.transports.docker["ghcr.io/cthtrifork/homeserver-bootc"][0] | .type == "sigstoreSigned" and .keyPath == "/etc/pki/cosign/cosign.pub" and .signedIdentity.type == "matchRepository"' /etc/containers/policy.json >/dev/null \
    || { echo "no signature requirement for ghcr.io/cthtrifork/homeserver-bootc in /etc/containers/policy.json"; exit 1; }
grep -q 'BEGIN PUBLIC KEY' /etc/pki/cosign/cosign.pub
grep -q 'use-sigstore-attachments: true' /etc/containers/registries.d/ghcr.yaml

echo "--- 20 largest installed packages ---"
rpm -qa --queryformat '%{SIZE} %{NAME}\n' | sort -rn | head -20 || true

echo "== System testing finished =="
