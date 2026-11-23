#!/usr/bin/env bash
set -eo pipefail

# Tests do things and see that they work: run the tools, start the sandbox, exercise the helper scripts. A check that only
# verifies what a test just did (the egress gateway's runtime state, the podman socket's mode) sits next to that test. How the
# image is configured (units, files, permissions, users, firewall rules) is checked by guard-tests.sh.

trap 'echo "💥 Error on line $LINENO (exit $?): last cmd: $BASH_COMMAND"' ERR

echo "== System testing (claude-vm) =="
id

echo "--- node ---"
# Node 24, with the full ICU data (nodejs24-full-i18n): without it Intl.Segmenter segfaults instead of throwing.
node --version | grep -q '^v24\.' || { echo "node: expected v24, got $(node --version)"; exit 1; }
graphemes="$(node -e 'console.log([...new Intl.Segmenter("en", { granularity: "grapheme" }).segment("héllo 👍🏽")].length)' || true)"
[ "$graphemes" = "7" ] || { echo "node: Intl.Segmenter is broken (got '$graphemes'): is nodejs24-full-i18n installed?"; exit 1; }

echo "--- egress gateway ---"
for u in nft ca proxy dns; do
    unit="claude-vm-egress-$u.service"
    if ! timeout 30 bash -c "until systemctl is-active --quiet $unit; do sleep 1; done"; then
        echo "$unit is not active"
        systemctl status --no-pager "$unit" || true
        journalctl -u "$unit" -b --no-pager -n 40 || true
        journalctl -b --no-pager -g 'avc:' | tail -n 20 || true
        exit 1
    fi
done
test -x /usr/libexec/claude-vm/egress-proxy
tcp="$(ss -ltnH)"
udp="$(ss -lunH)"
# each agent user has its own proxy on its own loopback address, so the proxy adds that user's token, and the containers share a third
# that passes TLS through; dnsmasq answers the DNS
for addr in 127.0.0.2 127.0.0.3 127.0.0.4; do
    grep -qF "$addr:443" <<<"$tcp"
    grep -qF "$addr:80" <<<"$tcp"
done
grep -qF '127.0.0.55:53' <<<"$udp"
# the proxy binary is installed under /usr/libexec (bin_t); in the packaged httpd_t domain SELinux denies its upstream connections
proxy_label="$(ps -o label= -C egress-proxy | head -n 1)"
echo "egress-proxy runs as: $proxy_label"
if grep -qF httpd_t <<<"$proxy_label"; then echo "egress-proxy must not run in httpd_t"; exit 1; fi
# the allowlist in iron-proxy.yaml is the only list
test -s /usr/share/claude-vm/egress/iron-proxy.yaml
# capture first: with pipefail, `cmd | grep -q` fails with SIGPIPE (141) when grep exits at the first match
allowed="$(claude-vm-egress allowed)"
grep -qx github.com <<<"$allowed"
grep -qx portableinfo.cloud <<<"$allowed"

echo "--- egress gateway: GitHub token swap and CA ---"
# one proxy per agent user, each holding that user's token only
for u in claude claude-rc-personal containers; do systemctl is-active --quiet "claude-vm-egress-proxy@$u.service"; done
# the CA key is readable by the proxy user only; the agents read neither it nor a token
[ "$(stat -c %a:%U:%G /var/lib/claude-vm/ca/ca.key)" = "640:root:ironproxy" ]
[ "$(stat -c %a:%U:%G /run/claude-vm/egress)" = "750:root:ironproxy" ]
# each proxy sees its own user's token directory only, under the same name
[ "$(sudo nsenter -t "$(systemctl show -p MainPID --value claude-vm-egress-proxy@claude.service)" -m ls /run/claude-vm/egress)" = current ]
for u in claude claude-rc-personal; do
    if sudo -u "$u" cat /var/lib/claude-vm/ca/ca.key >/dev/null 2>&1; then echo "$u can read the CA key"; exit 1; fi
    if sudo -u "$u" cat "/run/claude-vm/egress/$u/github-token" >/dev/null 2>&1; then echo "$u can read its token"; exit 1; fi
done
# the CA is in the system trust store
openssl verify -CAfile /etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem /var/lib/claude-vm/ca/ca.crt

echo "--- staged-update notice ---"
sudo bootc status --format json | jq -e '.status | has("staged")' >/dev/null
sudo /usr/libexec/claude-vm/note-staged-update
test ! -e /run/claude-vm/update-staged   # nothing is staged on a fresh install
sudo install -d /run/claude-vm && sudo touch /run/claude-vm/update-staged
sudo -u claude /usr/libexec/claude-vm/session-start-note | jq -e '.hookSpecificOutput.additionalContext | test("staged")' >/dev/null
sudo rm -f /run/claude-vm/update-staged
[ -z "$(sudo -u claude /usr/libexec/claude-vm/session-start-note)" ]

echo "--- Bash sandbox and podman socket ---"
# bubblewrap must start under the service's own hardening
sudo systemd-run --wait --pipe --collect -q -p User=claude \
    -p PrivateTmp=yes -p ProtectSystem=strict \
    bwrap --unshare-all --ro-bind / / --dev /dev --proc /proc true
# an agent can use its own podman socket, and the podman user can write the agent's workspace
timeout 60 bash -c 'until [ -S /run/claude-vm-podman/claude/podman.sock ]; do sleep 1; done'
[ "$(stat -c %U:%G:%a /run/claude-vm-podman/claude/podman.sock)" = "claude-podman:claude:660" ]
sudo -u claude test -w /run/claude-vm-podman/claude/podman.sock
sudo -u claude-podman test -w /var/home/claude/workspace

echo "✅ System testing finished"
