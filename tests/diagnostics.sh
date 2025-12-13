#!/usr/bin/env bash
set -euox pipefail

echo "== home directory tree =="
sudo tree -uag /home/ -L 4 --si --du
echo "== all users (getent passwd): =="
sudo getent passwd
echo "== all shadow (getent shadow): =="
sudo getent shadow
echo "== getent group wheel =="
sudo getent group wheel
echo "== /etc/subuid and /etc/subgid: =="
sudo cat /etc/subuid
sudo cat /etc/subgid
echo "== /etc/group: =="
sudo cat /etc/group
#echo "== systemd-sysusers config: =="
#systemd-sysusers --cat-config
#echo "== systemd-tmpfiles config: =="
#systemd-tmpfiles --cat-config
echo "== systemd-analyze critical-chain: =="
systemd-analyze critical-chain || true
echo "== authselect current =="
grep -E '^(passwd|shadow|group):' /etc/nsswitch.conf
authselect current
tree /etc/pam.d

#echo "== integrity (pwck): =="
#sudo pwck || true
