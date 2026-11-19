#!/usr/bin/env bash
set -eo pipefail

# Tests do things and see that they work: run the tools, start the sandbox, exercise the helper scripts. A check that only
# verifies what a test just did (the egress gateway's runtime state, the podman socket's mode) sits next to that test. How the
# image is configured (units, files, permissions, users, firewall rules) is checked by guard-tests.sh.

trap 'echo "💥 Error on line $LINENO (exit $?): last cmd: $BASH_COMMAND"' ERR

echo "== System testing (claude-vm) =="
id

echo "--- tools run ---"
# print only the first line of a tool's version output; not `cmd | head -n 1`: head exits early and, under pipefail, the SIGPIPE
# (141) fails the pipeline
first() {
    local out
    out="$("$@" 2>&1)"
    echo "${out%%$'\n'*}"
}
claude --version
first bash --version
python3 --version
pip3 --version
go version
first ffmpeg -version
first ffprobe -version
chromium-browser --version
podman --version
podman-compose --version
skopeo --version
crane version
first gh --version
git --version
jq --version
yq --version
first shellcheck --version
shfmt --version
yamllint --version
first make --version
hadolint --version
first actionlint -version
kubectl version --client
helm version --short
kustomize version
kubeconform -v
bwrap --version
first socat -V
ssh -V
lighthouse --version
npm --version

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
grep -qF '127.0.0.1:8443' <<<"$tcp"
grep -qF '127.0.0.1:8008' <<<"$tcp"
# the second agent user has its own pair of ports, so the proxy adds that user's token
grep -qF '127.0.0.1:8444' <<<"$tcp"
grep -qF '127.0.0.1:8009' <<<"$tcp"
grep -qF '127.0.0.55:53' <<<"$udp"
# the proxy binary is installed under /usr/libexec (bin_t); in the packaged httpd_t domain SELinux denies its upstream connections
proxy_label="$(ps -o label= -C egress-proxy | head -n 1)"
echo "egress-proxy runs as: $proxy_label"
if grep -qF httpd_t <<<"$proxy_label"; then echo "egress-proxy must not run in httpd_t"; exit 1; fi
# the allowlist (usr/share/claude-vm/egress/allowlist.txt) and its copies for the gateway and the sandbox (guard-tests.sh compares them)
for f in /usr/share/claude-vm/egress/{allowlist.txt,iron-proxy.yaml,dnsmasq-servers}; do test -s "$f"; done
claude-vm-egress allowed | grep -qx github.com
claude-vm-egress allowed | grep -qx portableinfo.cloud

echo "--- egress gateway: GitHub token swap and CA ---"
# one proxy per agent user, each holding that user's token only
for u in claude claude-rc-personal; do systemctl is-active --quiet "claude-vm-egress-proxy@$u.service"; done
# the CA key is readable by the proxy user only; the agents read neither it nor a token
[ "$(stat -c %a:%U:%G /var/lib/claude-vm/ca/ca.key)" = "640:root:ironproxy" ]
[ "$(stat -c %a:%U:%G /run/claude-vm/egress)" = "750:root:ironproxy" ]
# each proxy sees its own user's token directory only, under the same name
[ "$(sudo nsenter -t "$(systemctl show -p MainPID --value claude-vm-egress-proxy@claude.service)" -m ls /run/claude-vm/egress)" = current ]
for u in claude claude-rc-personal; do
    if sudo -u "$u" cat /var/lib/claude-vm/ca/ca.key >/dev/null 2>&1; then echo "$u can read the CA key"; exit 1; fi
    if sudo -u "$u" cat "/run/claude-vm/egress/$u/github-token" >/dev/null 2>&1; then echo "$u can read its token"; exit 1; fi
done
# the CA is in the system trust store and may only sign for allowlisted names
openssl verify -CAfile /etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem /var/lib/claude-vm/ca/ca.crt
openssl x509 -in /var/lib/claude-vm/ca/ca.crt -noout -ext nameConstraints | grep -qF 'DNS:github.com'

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
