#!/usr/bin/env bash
set -eo pipefail

trap 'echo "💥 Error on line $LINENO (exit $?): last cmd: $BASH_COMMAND"' ERR

echo "== System testing =="

echo "Running as"
id

echo "Verifying status for custom installed services..."
CORE_SERVICES="bootc-system-setup" # todo: make dynamic
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

echo "--- boot timing ---"
# wait for startup to finish so systemd-analyze reports final numbers; informational only, never fails the test
timeout 120 systemctl is-system-running --wait || true
systemd-analyze time || true
systemd-analyze critical-chain --no-pager || true
echo "--- 15 slowest units ---"
systemd-analyze blame --no-pager | head -15 || true

# 10-vscode.sh must install only the extensions that are missing. This uses the real `code` and the real marketplace.
# If the VM cannot install extensions (the marketplace is unreachable from CI), the skip path cannot be exercised: say
# so loudly instead of passing silently, and do not fail the test for an environment limit.
echo "--- vscode hook: install only missing extensions ---"
user_unit="bootc-user-setup@caspertdk.service"
echo "marketplace DNS and reachability from the VM (IPs can be compared with the dropped IPs in Hubble):"
for host in marketplace.visualstudio.com ms-vscode-remote.gallery.vsassets.io ms-vscode-remote.gallerycdn.vsassets.io \
    update.code.visualstudio.com vscode.download.prss.microsoft.com dc.services.visualstudio.com \
    mobile.events.data.microsoft.com open-vsx.org; do
    ips=$(getent ahostsv4 "$host" 2>/dev/null | awk '{print $1}' | sort -u | tr '\n' ' ' || true)
    status=$(curl -sS -o /dev/null --max-time 10 -w 'HTTP %{http_code}' "https://$host/" 2>&1 | tail -n 1 || true)
    echo "$host: ${ips:-no DNS answer} -> $status"
done
present=$(sudo -n -H -u caspertdk code --list-extensions 2>/dev/null | grep -c . || true)
echo "extensions installed after the first boot: $present"
if [ "$present" -eq 0 ]; then
    echo "::warning::No vscode extension could be installed in this VM (marketplace unreachable?): the install-only-missing path of 10-vscode.sh was NOT tested"
else
    since=$(date '+%Y-%m-%d %H:%M:%S')
    sudo -n systemctl restart "$user_unit"
    journal=$(sudo -n journalctl -u "$user_unit" --since "$since" --no-pager 2>&1)
    skipped=$(grep -c "already installed:" <<<"$journal" || true)
    reinstalled=$(grep -c "install-extension" <<<"$journal" || true)
    echo "second run: $skipped extension(s) skipped, $reinstalled install call(s) for missing ones"
    [ "$skipped" -ge "$present" ] || {
        echo "10-vscode.sh did not skip all $present installed extension(s)"
        exit 1
    }
    echo "✅ 10-vscode.sh skips installed extensions"
fi

echo "--- 20 largest installed packages ---"
rpm -qa --queryformat '%{SIZE} %{NAME}\n' | sort -rn | head -20 || true

echo "== System testing finished =="
