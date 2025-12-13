#!/usr/bin/env bash
set -euo pipefail

echo "Running as"
id

echo "Verifying status for custom installed services..."
CORE_SERVICES="bootc-system-setup" # todo: detect
echo "--- core services ---"
for s in $CORE_SERVICES; do
    systemctl is-active --quiet "$s" || {
        echo "Service not active: $s"
        systemctl status "$s" --no-pager || true
        exit 1
    }
done
echo "✅ core services are OK"
