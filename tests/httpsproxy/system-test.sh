#!/usr/bin/env bash
set -euox pipefail

echo "Running as"
id

echo "Verifying status for custom installed services..."
CORE_SERVICES="squid.service"
echo "--- core services ---"
for s in $CORE_SERVICES; do
    systemctl is-active --quiet "$s" || {
        echo "Service not active: $s"
        systemctl status "$s" --no-pager || true
        systemd-analyze critical-chain "$s"
        systemctl cat "$s"
        journalctl -xeu "$s"
        exit 1
    }
done
echo "✅ core services are OK"

echo "Testing HTTPS proxy through squid..."
curl --proxy http://localhost:3128 https://google.com -v
