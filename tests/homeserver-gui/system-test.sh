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

# 10-vscode.sh must install only the extensions that are missing. The CI VM cannot install real extensions (nothing
# ends up in ~/.vscode/extensions), so test the hook's logic with a stub `code` that records installs: the first run
# must install something and the second run must install nothing more. These are real assertions.
echo "--- vscode hook: install only missing extensions ---"
user_unit="bootc-user-setup@caspertdk.service"
stub_dir=/var/tmp/fake-code
state="$stub_dir/installed"
sudo -n install -d -m 0777 "$stub_dir"
sudo -n install -m 0666 /dev/null "$state"
sudo -n tee "$stub_dir/code" >/dev/null <<'EOF'
#!/usr/bin/env bash
state=/var/tmp/fake-code/installed
case "$1" in
    --list-extensions) cat "$state" ;;
    --install-extension) echo "$2" >>"$state" ;;
esac
EOF
sudo -n chmod 0755 "$stub_dir/code"
sudo -n mkdir -p /run/systemd/system/bootc-user-setup@.service.d
printf '[Service]\nEnvironment=PATH=%s:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin\n' "$stub_dir" |
    sudo -n tee /run/systemd/system/bootc-user-setup@.service.d/10-fake-code.conf >/dev/null
sudo -n systemctl daemon-reload
sudo -n systemctl restart "$user_unit"
first=$(grep -c . "$state" || true)
sudo -n systemctl restart "$user_unit"
second=$(grep -c . "$state" || true)
echo "extensions installed after the first run: $first, after the second run: $second"
sudo -n rm -rf /run/systemd/system/bootc-user-setup@.service.d "$stub_dir"
sudo -n systemctl daemon-reload
[ "$first" -ge 1 ] || {
    echo "10-vscode.sh did not install anything through the stubbed code"
    exit 1
}
[ "$second" -eq "$first" ] || {
    echo "10-vscode.sh installed extensions again on the second run"
    exit 1
}
echo "✅ 10-vscode.sh installs only missing extensions"

echo "--- 20 largest installed packages ---"
rpm -qa --queryformat '%{SIZE} %{NAME}\n' | sort -rn | head -20 || true

echo "== System testing finished =="
