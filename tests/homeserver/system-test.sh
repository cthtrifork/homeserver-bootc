#!/usr/bin/env bash
set -euo pipefail

echo "Running as"
id

echo "Verifying status for custom installed services..."
CORE_SERVICES="pinggy.service homer-groups.service setup-tmpfiles.service" # todo: detect
echo "--- core services ---"
for s in $CORE_SERVICES; do
    systemctl is-active --quiet "$s" || {
    echo "Service not active: $s"
    systemctl status "$s" --no-pager || true
    exit 1
    }
done
echo "✅ core services are OK"

#/usr/bin/systemd-tmpfiles --cat-config

echo "== caspertdk: home directory is valid =="
sudo test -d /home/caspertdk && echo "✅ home directory exists" || { echo "❌ home directory missing"; exit 1; }
sudo tree -uag /home/caspertdk 
sudo getent passwd caspertdk
sudo test -f /home/caspertdk/.ssh/authorized_keys && echo "✅ authorized_keys exists" || { echo "❌ authorized_keys missing"; exit 1; }
echo "✅ homed user creation + authorized keys OK"

echo "== debug =="
echo "all users (/etc/passwd):"
sudo cat /etc/passwd
echo "getent group wheel"
sudo getent group wheel
echo "/etc/subuid and /etc/subgid:"
sudo cat /etc/subuid
sudo cat /etc/subgid
#echo "/etc/subuid.bak and /etc/subgid.bak:"
#sudo cat /etc/subuid.bak
#sudo cat /etc/subgid.bak
echo "/etc/group:"
sudo cat /etc/group

# check if env var ENV_LOAD is loaded
if [ -z "${ENV_LOAD:-}" ]; then
    echo "ENV_LOAD is not set"
    exit 1
fi
echo "✅ ENV_LOAD is set to '$ENV_LOAD'. /etc/profile.d/* is working as intended."

echo "Checking if user is in docker group"
docker run --rm hello-world && echo "✅ Docker is ready"

echo "Checking github Auth status"
echo "GitHub token fingerprint: $(printf "%s" "$GITHUB_TOKEN" | cut -c1-7)"

gh auth status && echo "✅ Github is ready"
