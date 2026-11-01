# This VM

You are running on a bootc VM (`claude-vm`) as the unprivileged user `claude`. There is no sudo.

## SSH access from outside

The VM can be reached over SSH through a free Pinggy tunnel (`claude-pinggy.service`, opt-in). The public address
is random and changes whenever the tunnel restarts (about hourly), so never rely on an address you saw earlier.

- To tell the user how to SSH in, run `claude-vm-ssh-address` and give them its output (`ssh -p <port> caspertdk@<host>`).
- If it prints "No tunnel address yet", the tunnel is not running. The user enables it with
  `sudo systemctl enable --now claude-pinggy` (you cannot: no sudo). Check with `systemctl status claude-pinggy`.
- Login is key-only as `caspertdk`; you have no access to those keys and do not need them.
