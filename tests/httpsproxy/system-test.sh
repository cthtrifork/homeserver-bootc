#!/usr/bin/env bash
set -euox pipefail

echo "Running as"
id

echo "squid -v"
squid -v || true

sudo -u squid /usr/sbin/squid -N -d1 -f /etc/squid/squid.conf
exit 1
 
echo "Verifying status for custom installed services..."
CORE_SERVICES="squid.service"
echo "--- core services ---"
for s in $CORE_SERVICES; do
    systemctl is-active --quiet "$s" || {
        echo "Service not active: $s"
        systemctl status "$s" --no-pager || true
        systemd-analyze critical-chain "$s" || true
        systemctl cat "$s"
        journalctl -xeu "$s"
        sudo systemctl stop "$s"
        /usr/sbin/squid -N -d1 -f /etc/squid/squid.conf
        exit 1
    }
done
echo "✅ core services are OK"

echo "Testing HTTPS proxy through squid..."
curl --proxy http://localhost:3128 https://google.com -v
echo "First request done, should be a MISS"
curl --proxy http://localhost:3128 https://google.com -v
echo "Second request done, should be a HIT"

curl --proxy https://localhost:3138 https://github.com/getsops/sops/releases/download/v3.11.0/sops-3.11.0-1.x86_64.rpm -v

sudo grep "TCP_HIT/200" /var/log/squid/access.log || {
    echo "HTTPS proxy test failed, no TCP_HIT/200 found in access.log"
    sudo tail -n 100 /var/log/squid/access.log
    exit 1
}
echo "✅ HTTPS proxy through squid is OK"
