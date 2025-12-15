#!/usr/bin/env bash
set -euo pipefail

echo "Running as"
id

ls -ldZ /var/log/squid /var/log/squid/*
sudo restorecon -R -v /var/log/squid

echo "Verifying status for custom installed services..."
CORE_SERVICES="prepare-squid.service squid.service"
echo "--- core services ---"
for s in $CORE_SERVICES; do
    systemctl is-active --quiet "$s" || {
        echo "Service not active: $s"
        systemctl status "$s" --no-pager || true
        systemctl cat "$s"
        journalctl -xeu "$s"
        sudo systemctl start "$s"
        exit 1
    }
done
echo "✅ core services are OK"

echo "Testing HTTPS proxy through squid..."
curl --proxy http://localhost:3128 https://google.com -v
