#!/usr/bin/env bash
set -euo pipefail

echo "Running as"
id


echo "== squid.service status =="
journalctl -u squid.service -b --no-pager
systemctl cat squid
coredumpctl list squid || true
coredumpctl info squid || true

#ls -ldZ /var/log/squid

#sudo restorecon -Rv /var/log/squid /var/spool/squid

sudo ls -lZ /var/log/squid /var/log/squid/squid.out 2>/dev/null || true

# Recreate squid.out with known-good ownership/permissions
#sudo rm -f /var/log/squid/squid.out
#sudo install -o squid -g squid -m 0640 /dev/null /var/log/squid/squid.out

# Ensure SELinux contexts are correct on squid log+cache paths
#sudo restorecon -Rv /var/log/squid /var/spool/squid

# Re-init cache dirs (only affects spool, but good to do while we're here)
#sudo -u squid /usr/sbin/squid -z -f /etc/squid/squid.conf


echo "== start squid =="
sudo systemctl daemon-reload || true
sudo systemctl reset-failed squid.service || true
sudo systemctl start squid.service || true
journalctl -xeu squid.service

sudo cat /var/log/squid/* | tail -n 100

echo "Verifying status for custom installed services..."
CORE_SERVICES="prepare-squid.service squid.service"
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