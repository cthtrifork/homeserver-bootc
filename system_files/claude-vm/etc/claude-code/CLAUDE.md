# This VM

You are running on a bootc VM (`claude-vm`) as the unprivileged user `claude`. There is no sudo.

## Filesystem (bootc, image-based OS)

- `/usr` is read-only and part of the OS image; you cannot install packages (no `dnf`, no sudo). Do not try to work
  around it. Tools you need beyond the image go in your home directory: `npm -g` (prefix `~/.npm-global`),
  `pip install --user`, `go install` (`~/go/bin`) are already on `PATH`.
- Work in `~/workspace`. The Bash sandbox lets commands write only there and to `~/.npm-global`, `~/.npm`, `~/.local`,
  `~/.cache` and `~/go`, and reach only the allowlisted hosts (GitHub, npm, PyPI, Go, common container registries).
  Everything you start, including podman containers, goes through an egress gateway that blocks all other hosts
  (DNS lookups are refused, connections reset). Approving a prompt does not change that; the user adds a host by
  editing `build_files/claude-vm/egress-allowlist.txt` and rebuilding the image. If a command fails with a permission
  or network error, say so and name the host instead of retrying.
- `podman` and `podman-compose` (the provider behind `podman compose`) are excluded from the sandbox and allowed without an
  approval prompt; use them freely, including `podman compose up --build`. They are rootless and their containers are
  confined by the same egress gateway. There is no Docker.
- Git over HTTPS uses `gh` with the seeded `GH_TOKEN`. There are no SSH keys on this VM, so use `https://` remotes.
- The OS updates nightly at 03:00 (`bootc upgrade --apply`) and the VM reboots into a new image, which ends running
  sessions. You cannot reboot it yourself; do not try to apply updates.
- `/etc/claude-code/` (managed settings and this file) is root-owned. You cannot and should not change your own policy.

## SSH access from outside

The VM can be reached over SSH through a free Pinggy tunnel (`claude-pinggy.service`, opt-in). The public address
is random and changes whenever the tunnel restarts (about hourly), so never rely on an address you saw earlier.

- To tell the user how to SSH in, run `claude-vm-ssh-address` and give them its output (`ssh -p <port> caspertdk@<host>`).
- If it prints "No tunnel address yet", the tunnel is not running. The user enables it with
  `sudo systemctl enable --now claude-pinggy` (you cannot: no sudo). Check with `systemctl status claude-pinggy`.
- Login is key-only as `caspertdk`; you have no access to those keys and do not need them.

## Agent guidelines

@AGENTS.md
