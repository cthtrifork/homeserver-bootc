#!/usr/bin/env bash
set -euox pipefail

echo "Running as"
id

echo "Verifying status for custom installed services..."
CORE_SERVICES="prepare-squid.service squid.service"
echo "--- core services ---"
for s in $CORE_SERVICES; do
    systemctl is-active --quiet "$s" || {
        echo "Service not active: $s"
        systemctl status "$s" --no-pager || true
        systemctl cat "$s"
        journalctl -xeu "$s"
        exit 1
    }
done
echo "✅ core services are OK"

echo "Testing HTTPS proxy through squid..."
curl --proxy http://localhost:3128 https://google.com -v

curl --proxy https://localhost:3138 https://github.com/getsops/sops/releases/download/v3.11.0/sops-3.11.0-1.x86_64.rpm -v | grep "TCP_HIT/200"
