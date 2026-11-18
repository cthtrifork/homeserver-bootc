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
for c in bash python3 pip3 node npm go chromium-browser ffmpeg ffprobe podman podman-compose skopeo crane gh git jq yq shellcheck shfmt yamllint make hadolint actionlint kubectl helm kustomize kubeconform bwrap socat ssh; do
    command -v "$c" >/dev/null || { echo "missing: $c"; exit 1; }
done

test -d /usr/lib/node_modules/playwright
node --version | grep -q '^v24\.' || { echo "node: expected v24, got $(node --version)"; exit 1; }
lighthouse --version

# Node needs the full ICU data (nodejs24-full-i18n): without it Intl.Segmenter segfaults instead of throwing.
graphemes="$(node -e 'console.log([...new Intl.Segmenter("en", { granularity: "grapheme" }).segment("héllo 👍🏽")].length)' || true)"
[ "$graphemes" = "7" ] || { echo "node: Intl.Segmenter is broken (got '$graphemes'): is nodejs24-full-i18n installed?"; exit 1; }

echo "--- services ---"
# enabled, but idle until the GitHub token is seeded and claude is signed in
systemctl is-enabled --quiet claude-remote-control.service
# personal Claude login (own Unix user claude-rc-personal): opt-in, independent of the claude service
systemctl cat claude-remote-control-rc-personal.service >/dev/null
# free Pinggy SSH tunnel is opt-in: present but neither enabled nor running
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
tcp="$(ss -ltnH)"
udp="$(ss -lunH)"
grep -qF '127.0.0.1:8443' <<<"$tcp"
grep -qF '127.0.0.1:8008' <<<"$tcp"
grep -qF '127.0.0.55:53' <<<"$udp"
# one allowlist (build_files/claude-vm/egress-allowlist.txt) feeds the gateway and the sandbox's allowedDomains
for f in /usr/share/claude-vm/egress/{allowlist.txt,nginx-allow.map,dnsmasq-servers}; do test -s "$f"; done
claude-vm-egress allowed | grep -qx github.com

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
[ "$(id -u claude-rc-personal)" = "1101" ]
test -e /var/lib/systemd/linger/claude-rc-personal
# each agent user has its own GitHub App; the refresher is a per-user template
systemctl cat 'claude-vm-github-token@claude-rc-personal.service' 'claude-vm-github-token@claude-rc-personal.timer' >/dev/null
test -e /var/lib/systemd/linger/claude
timeout 60 bash -c 'until [ -d /run/user/1100 ]; do sleep 1; done'
# containers run as separate UIDs (claude-vm-podman@<agent>.service), not as the agents
[ "$(id -u claude-podman)" = "1200" ]
[ "$(id -u claude-rc-personal-podman)" = "1201" ]
# the agents use the wrapper (first on PATH), which talks to the API of their podman user
test -x /usr/libexec/claude-vm/bin/podman
test -x /usr/libexec/claude-vm/bin/claude-vm-dnf
timeout 60 bash -c 'until [ -S /run/claude-vm-podman/claude/podman.sock ]; do sleep 1; done'
sudo -u claude test -w /run/claude-vm-podman/claude/podman.sock
# the podman user's workspace access is shared by ACL
sudo -u claude-podman test -w /var/home/claude/workspace

echo "--- usage telemetry ---"
jq -e '.env.CLAUDE_CODE_ENABLE_TELEMETRY == "1" and .env.OTEL_EXPORTER_OTLP_PROTOCOL == "http/protobuf" and .env.OTEL_METRICS_INCLUDE_SESSION_ID == "false"' /etc/claude-code/managed-settings.json >/dev/null
claude-vm-egress allowed | grep -qx portableinfo.cloud

echo "✅ System testing finished"
