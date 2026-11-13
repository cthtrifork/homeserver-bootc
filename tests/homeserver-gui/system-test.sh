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
echo "--- failed units ---"
systemctl --failed --no-pager || true
echo "--- user-setup hook timings ---"
sudo -n journalctl -u 'bootc-user-setup@*' -o short-precise --no-pager 2>&1 | grep -E "user-setup:|Finished|Failed" | tail -20 || true

# The VS Code extensions are installed after boot by a unit that waits for the network, and a second run must not
# install anything again (real code, real marketplace).
echo "--- vscode extensions: installed after boot, only the missing ones ---"
user_unit="bootc-vscode-extensions@caspertdk.service"
# blocks until the boot run has finished (or runs the unit if it already has)
sudo -n timeout 900 systemctl start "$user_unit"
present=$(sudo -n -H -u caspertdk code --list-extensions 2>/dev/null | grep -c . || true)
echo "extensions installed: $present"
if [ "$present" -eq 0 ]; then
    echo "::warning::No vscode extension could be installed in this VM (marketplace unreachable?): the install-only-missing path was NOT tested"
else
    since=$(date '+%Y-%m-%d %H:%M:%S')
    sudo -n systemctl start "$user_unit"
    reinstalled=$(sudo -n journalctl -u "$user_unit" --since "$since" --no-pager 2>&1 | grep -c "install-extension" || true)
    echo "second run: $reinstalled install call(s)"
    [ "$reinstalled" -eq 0 ] || {
        echo "the extensions unit tried to install again although $present extensions are present"
        exit 1
    }
    echo "✅ the extensions unit installs only missing extensions"
fi

echo "--- 20 largest installed packages ---"
rpm -qa --queryformat '%{SIZE} %{NAME}\n' | sort -rn | head -20 || true

echo "== System testing finished =="
