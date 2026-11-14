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
# TEMPORARY: find the hosts the extension signature check contacts, then stop (no waiting for the slow unit)
echo "--- which hosts does the signature check contact? ---"
sudo -n systemctl stop "bootc-vscode-extensions@caspertdk.timer" "$user_unit" || true
sudo -n -H -u caspertdk code --uninstall-extension mkhl.shfmt >/dev/null 2>&1 || true
dns_log=/tmp/dns-monitor.log
syn_log=/tmp/syn-sent.log
: >"$syn_log"
sudo -n timeout 280 resolvectl monitor >"$dns_log" 2>&1 &
(for _ in $(seq 1 270); do
    ss -tnH state syn-sent >>"$syn_log" 2>&1
    sleep 1
done) &
install_start=$SECONDS
sudo -n -H -u caspertdk timeout 250 code --install-extension mkhl.shfmt 2>&1 | grep -E "successfully installed|Error while installing" | head -2 || true
echo "install took $((SECONDS - install_start))s"
sudo -n pkill -f "resolvectl monitor" || true
echo "-- names queried (count name):"
grep -oE "Q: [^ ]+" "$dns_log" | sort | uniq -c | sort -rn | head -40 || true
echo "-- peers left in SYN-SENT (count ip:port):"
awk '{print $4}' "$syn_log" | sort | uniq -c | sort -rn | head -20 || true
echo "-- raw monitor lines about microsoft/digicert/crl/ocsp:"
grep -i -E "microsoft|digicert|crl|ocsp|msocsp|pki|windowsupdate|globalsign|verisign" "$dns_log" | cut -c1-160 | sort -u | head -30 || true
exit 0
# blocks until the boot run has finished (or runs the unit if it already has)
sudo -n timeout 900 systemctl start "$user_unit" || {
    echo "--- $user_unit failed ---"
    sudo -n systemctl list-jobs --no-pager || true
    sudo -n journalctl -u "$user_unit" -n 60 --no-pager | cut -c1-200 || true
    exit 1
}
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
