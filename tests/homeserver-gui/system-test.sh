#!/usr/bin/env bash
set -euo pipefail

echo "Running as"
id

echo "Verifying status for custom installed services..."
CORE_SERVICES="bootc-system-setup setup-tmpfiles.service" # todo: detect
echo "--- core services ---"
for s in $CORE_SERVICES; do
    systemctl is-active --quiet "$s" || {
        echo "Service not active: $s"
        systemctl status "$s" --no-pager || true
        exit 1
    }
done
echo "✅ core services are OK"

echo "== systemd-sysusers config: =="
systemd-sysusers --cat-config
echo "== all users (getent passwd): =="
sudo getent passwd
echo "== all shadow (getent shadow): =="
sudo getent shadow
echo "== systemd-analyze critical-chain: =="
systemd-analyze critical-chain
echo "== integrity (pwck): =="
sudo pwck || true