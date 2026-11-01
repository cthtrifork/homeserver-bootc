# This VM

You are running on a bootc VM (`claude-vm`) as the unprivileged user `claude`. There is no sudo.

## Filesystem (bootc, image-based OS)

- `/usr` is read-only and part of the OS image; you cannot install packages (no `dnf`, no sudo). Do not try to work
  around it. Tools you need beyond the image go in your home directory: `npm -g` (prefix `~/.npm-global`),
  `pip install --user`, `go install` (`~/go/bin`) are already on `PATH`.
- Work in `~/workspace`. The Bash sandbox lets commands write only there and to `~/.npm-global`, `~/.npm`, `~/.local`,
  `~/.cache` and `~/go`, and reach only the allowlisted hosts (GitHub, npm, PyPI, Go, common container registries);
  other hosts prompt the user. If a command fails with a permission or network error, say so instead of retrying.
- `podman` is excluded from the sandbox and always asks for approval. It is rootless; there is no Docker.
- Git over HTTPS uses `gh` with the seeded `GH_TOKEN`. There are no SSH keys on this VM, so use `https://` remotes.
- The OS updates nightly but only takes effect after a reboot, which you cannot do. If a new image is staged, tell
  the user once; do not try to apply it.
- `/etc/claude-code/` (managed settings and this file) is root-owned. You cannot and should not change your own policy.

## SSH access from outside

The VM can be reached over SSH through a free Pinggy tunnel (`claude-pinggy.service`, opt-in). The public address
is random and changes whenever the tunnel restarts (about hourly), so never rely on an address you saw earlier.

- To tell the user how to SSH in, run `claude-vm-ssh-address` and give them its output (`ssh -p <port> caspertdk@<host>`).
- If it prints "No tunnel address yet", the tunnel is not running. The user enables it with
  `sudo systemctl enable --now claude-pinggy` (you cannot: no sudo). Check with `systemctl status claude-pinggy`.
- Login is key-only as `caspertdk`; you have no access to those keys and do not need them.
