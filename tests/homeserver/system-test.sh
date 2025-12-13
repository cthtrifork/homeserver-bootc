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

