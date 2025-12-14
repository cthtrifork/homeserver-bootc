#!/usr/bin/env bash
set -euo pipefail

echo "Running as"
id

sleep 15

echo "== squid.service status =="
journalctl -u squid.service -b --no-pager
systemctl cat squid
coredumpctl list squid || true
coredumpctl info squid || true

echo "== start squid =="
systemctl daemon-reload || true
systemctl reset-failed squid.service || true
systemctl start squid.service || true


cat /var/log/squid/* | tail -n 100

echo "Verifying status for custom installed services..."
CORE_SERVICES="squid.service"
echo "--- core services ---"
for s in $CORE_SERVICES; do
    systemctl is-active --quiet "$s" || {
        echo "Service not active: $s"
        systemctl status "$s" --no-pager || true
        exit 1
    }
done
echo "✅ core services are OK"

echo "Testing HTTPS proxy through squid..."
curl --proxy http://localhost:3128 https://google.com -v