# claude-vm

Back to the [main README](../../README.md).

`claude-vm.containerfile` builds `claude-vm-bootc`: a minimal VM that runs
[`claude remote-control`](https://code.claude.com/docs/en/remote-control) as the unprivileged user `claude`, so you can
drive it from claude.ai/code or the Claude app. Layout mirrors the home server: `system_files/claude-vm/`, numbered
`/etc/tmpfiles.d/` files and `tests/claude-vm/`.

## What is in it

- **No secrets.** The build takes none: no registry, age or SSH keys. You seed a GitHub token by hand and sign in to
  Claude interactively (first-boot steps below). SSH host keys are generated on the VM at first boot.
- **SSH uses the same public keys as the home server.** `authorized_keys.pub` is copied from
  `system_files/homeserver/` at build time and installed for `caspertdk` by `11-caspertdk-ssh.conf`. Login is key-only.
  `caspertdk` has sudo; `claude` has none. Only public keys are used, so commits on the VM are not SSH-signed.
- **Tools for Claude:** bash, python3/pip, node/npm, go, skopeo, crane, git/gh and rootless podman. `/usr` is
  read-only, so `npm -g`, `pip --user` and `go install` use the home directory.
- **Egress allowlist:** everything the `claude` user runs, rootless podman containers included, can only reach the hosts in
  `build_files/claude-vm/egress-allowlist.txt`; see [Egress gateway](#egress-gateway).
- **Versions:** Claude Code and crane are pinned by `ARG ... # renovate:` lines (Renovate's regex manager covers
  `*.containerfile`). Everything else is a Fedora package that moves with the `fedora-bootc` base image.
- **Updates:** `bootc-fetch-apply-updates.timer` runs daily at 00:30 with the same drop-ins as `homeserver-gui`, but
  `bootc upgrade` only stages the image. It takes effect at your next reboot, since a reboot would end a running
  session. A staged update leaves a marker in `/run` (gone after reboot), and a managed `SessionStart` hook tells
  Claude, and so you, when a session starts or resumes.

## First-boot setup (once per VM)

```sh
ssh caspertdk@<vm>

# 1. Seed the GitHub token (hidden prompt or stdin; never an argument). Private keys are refused.
sudo claude-vm-seed-github-token

# 2. Sign in as the service user. Remote Control needs a claude.ai login (API keys are not supported).
sudo -iu claude
cd ~/workspace && claude          # /login, trust the folder, then exit
claude remote-control             # answer 'y' to "Enable Remote Control?", then Ctrl-C
exit

# 3. Start the service (enabled, but idle until steps 1 and 2 are done)
sudo systemctl restart claude-remote-control
journalctl -u claude-remote-control -f     # shows the session URL
```

Rotate the token by re-running step 1. It lives only in `/etc/claude-vm/github-token` (root, 0600) and reaches the
service as a systemd credential. The Claude login lives in `/var/home/claude/.claude/` and survives upgrades.

## Reaching the VM over SSH (free Pinggy tunnel)

`claude-pinggy.service` opens a free [Pinggy](https://pinggy.io/docs/run_tunnel_on_startup/linux/) TCP tunnel to the
local sshd (`ssh -p 443 -R0:localhost:22 tcp@free.pinggy.io`), like `pinggy.service` on the home server, so you can
log in without knowing the VM's IP. It needs **no account or token**, which keeps the image secret-free. It runs as a
throwaway `DynamicUser`. It is **opt-in**: shipped disabled, so a fresh VM (and the CI e2e VM) opens no tunnel until
you run `sudo systemctl enable --now claude-pinggy`.

```sh
# on the VM (after enabling the service above): print the current address
claude-vm-ssh-address        # ssh -p 41234 caspertdk@abcde-1-2-3-4.a.free.pinggy.link
# or: journalctl -u claude-pinggy | grep 'tunnel up'

# from your machine
ssh -p 41234 caspertdk@abcde-1-2-3-4.a.free.pinggy.link
```

- **The address is random and changes** each time the tunnel starts. Free tunnels are closed after about 60 minutes,
  and systemd then restarts the tunnel with a new address, so re-run `claude-vm-ssh-address` if a login stops working.
  For a fixed address use a paid Pinggy token as on the home server (not wired up here, to keep the image secret-free).
- **Anyone can reach the port, so only the key matters.** Password login is off and only the keys in
  `authorized_keys.pub` work, but the sshd is on the internet and will see scan traffic. Turn it off with
  `sudo systemctl disable --now claude-pinggy` when you do not need it.

## Security model

- **Policy:** `/etc/claude-code/managed-settings.json` is root-owned and has the highest precedence, so `claude`
  cannot change it. It rejects `--dangerously-skip-permissions` and runs only managed hooks (`allowManagedHooksOnly`),
  so hooks in repositories Claude clones are ignored ([managed settings](https://code.claude.com/docs/en/managed-settings.md)).
- **Bash sandbox:** Claude Code's built-in sandbox is required and cannot be bypassed by the model
  ([sandboxing](https://code.claude.com/docs/en/sandboxing.md)). Shell commands run in `bubblewrap`, can write only to
  `~/workspace`, `~/.npm-global`, `~/.npm`, `~/.local`, `~/.cache` and `~/go`, and can reach only the hosts in
  `allowedDomains` (the same list the [egress gateway](#egress-gateway) enforces, which blocks every other host).
  `~/.claude/.credentials.json` is hidden from them. Because commands are
  confined they run without a prompt (`autoAllowBashIfSandboxed`); set it to `false` to be asked every time.
  - **`podman *` is excluded:** rootless podman cannot run inside the sandbox. Podman still asks for approval, but once
    approved it and its containers are outside the sandbox. Their network is still confined by the
    [egress gateway](#egress-gateway) below.
  - It is a guardrail, not a hard boundary: the sandbox proxy filters by hostname without inspecting TLS, broad hosts
    such as `github.com` can carry data out, and MCP servers and hooks are not covered.
  - The service omits `ProtectKernelTunables`, because it stops bubblewrap mounting its own `/proc`.
- **A Remote Control session is a shell as `claude`.** Whoever controls your claude.ai session controls the VM. Turn on
  **Require trusted devices** in your account settings (beta) ([docs](https://code.claude.com/docs/en/remote-control.md#trusted-devices)).
- **GitHub token:** use a fine-grained token limited to the repositories Claude should touch, with only the
  permissions it needs (typically Contents and Pull requests read/write) and a short expiry.
- **Data and terms:** while connected, the session transcript is stored on Anthropic's servers
  ([connection and security](https://code.claude.com/docs/en/remote-control.md#connection-and-security)). Use your own
  login and do not share it ([legal](https://code.claude.com/docs/en/legal-and-compliance.md)). Do not set
  `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC`: it also disables Remote Control.

## Egress gateway

Everything the `claude` user starts, including rootless podman containers, can only reach hosts on one allowlist. It is
enforced in the kernel for the user's UID, so it does not depend on the sandbox or on podman cooperating.

| Unit | What it does |
| --- | --- |
| `claude-vm-egress-nft` | nftables (`/usr/share/claude-vm/egress.nft`). For UID 1100 and the podman subuid range (100000-165535, which host-network containers run as): redirects DNS to `:5353`, HTTPS to `:3129` and HTTP to `:3128` on loopback, and rejects everything else (QUIC/UDP, SSH, other ports, IPv6). rootless podman's `pasta` opens its sockets as `claude`, so container traffic is matched too. |
| `claude-vm-egress-proxy` | nginx, no TLS interception. Reads the SNI of a TLS handshake (or the HTTP `Host`) and connects to that name itself; unlisted names are dropped (403 for HTTP), and so is an IP address with no SNI. |
| `claude-vm-egress-dns` | dnsmasq. Forwards only allowlisted domains to the system resolver and refuses the rest. |

Root, `caspertdk`, `bootc upgrade`, dnf and the Pinggy tunnel (a `DynamicUser`) are **not** restricted.
`claude-remote-control` requires all three units: without them it does not start, and the user has no network anyway.

**One allowlist.** `build_files/claude-vm/egress-allowlist.txt` has one domain per line, and a domain also covers its
subdomains. `build_files/claude-vm/egress_allowlist.py` runs during the image build and **fails the build** on an
invalid, duplicate or redundant entry (wildcards, uppercase, IPs, ports, `api.github.com` next to `github.com`), reporting
every problem with its line number. From the list it derives:

- `sandbox.network.allowedDomains` in the managed settings (`d` and `*.d` per entry);
- `nginx-allow.map` and `dnsmasq-servers` in `/usr/share/claude-vm/egress/`, which the static configs
  `/usr/share/claude-vm/egress-nginx.conf` and `egress-dnsmasq.conf` include.

Nothing is generated at boot. To allow another host, add it to `egress-allowlist.txt` and rebuild the image. That also
allows it in the Claude sandbox, so approving a sandbox prompt for a host is not enough: the gateway is stricter.

**What a block looks like.** Usually a DNS failure ("could not resolve host"), because the name is refused before any
connection is made. A listed name that resolves but is blocked at the proxy shows as a connection reset (HTTPS) or a 403
(HTTP). `ssh` and git-over-SSH are blocked; use HTTPS remotes.

**Limits.** Filtering is by name, not content. A listed host that is a shared CDN or a broad service (`github.com`,
`ghcr.io`, `pypi.org`) can still carry data out, domain fronting to a listed CDN is possible, and DNS queries for listed
domains can carry data.

## Operating notes

- **Monitoring:** nothing extra is installed; the docs recommend none. systemd restarts the service
  (`Restart=always`). Server mode exits after about 10 minutes without network, and a restart in the same directory
  brings its sessions back for about four hours ([limitations](https://code.claude.com/docs/en/remote-control.md#limitations)).
  An unreachable VM shows as an offline session at claude.ai/code. For a push when a task finishes or needs a
  decision, run `/config` once in an interactive `claude` as `claude` and enable the push options
  ([push notifications](https://code.claude.com/docs/en/remote-control.md#mobile-push-notifications)).
- **Claude knows about the tunnel.** `/etc/claude-code/CLAUDE.md` is managed memory loaded in every session. It tells
  Claude to run `claude-vm-ssh-address` when you ask how to SSH in, so you can just ask it.
- **`/var` and `/etc` are not re-applied on upgrade.** tmpfiles `C` never overwrites, so `authorized_keys` is copied from
  the image only if absent. **Revoking a key in a later image does not reach VMs that already booted**: edit
  `~caspertdk/.ssh/authorized_keys` on each VM. A hand-edited `/etc` file stops following the image; keep local
  policy changes in `/etc/claude-code/managed-settings.d/*.json` and list drift with `ostree admin config-diff`.

## Build a disk image

`create-vmdk-image.yaml` accepts `claude-vm-bootc`. Locally:

```sh
sudo podman run --rm -it --privileged -v ./out:/output -v ./config.toml:/config.toml:ro \
  quay.io/centos-bootc/bootc-image-builder:latest --type qcow2 --config /config.toml \
  ghcr.io/cthtrifork/homeserver-bootc/claude-vm-bootc:latest
```

CI builds it like the other images (`claude-vm` in the build matrix).

## Policy at a glance

`system_files/claude-vm/etc/claude-code/managed-settings.json` (shipped to `/etc/claude-code/`):

| Key | Value | Why |
| --- | --- | --- |
| `permissions.disableBypassPermissionsMode` | `"disable"` | `--dangerously-skip-permissions` is rejected |
| `allowManagedHooksOnly` | `true` | only the hooks in this file run |
| `hooks.SessionStart` | `session-start-note` | reports a staged OS update |
| `sandbox.enabled` / `failIfUnavailable` | `true` | a missing sandbox stops the service instead of running unsandboxed |
| `sandbox.allowUnsandboxedCommands` | `false` | the model cannot retry a command outside the sandbox |
| `sandbox.excludedCommands` | `["podman *"]` | rootless podman cannot run inside the sandbox |
| `sandbox.filesystem.allowWrite` | `~/.npm-global`, `~/.npm`, `~/.local`, `~/.cache`, `~/go` | user-space installs and caches |
| `sandbox.filesystem.denyRead` | `~/.claude/.credentials.json` | the login token is hidden from commands |
| `sandbox.network.allowedDomains` | generated at build time from `egress-allowlist.txt` | the same list the [egress gateway](#egress-gateway) enforces |

## Tests

`tests/claude-vm/` runs in QEMU when a (non-draft) pull request has the `e2e` label. The system test checks the tools,
that the service is enabled but idle, that the Pinggy tunnel unit is present but not enabled, the staged-update notice,
the policy, that `bubblewrap` starts under the service's hardening, users and SSH, home directories and lingering, that
no key or token file is on the VM, and the egress gateway (the three units are active, the nftables table is loaded, the
generated allowlist files exist and the sandbox's `allowedDomains` match the allowlist).

The user test checks that the seed helper refuses a private key, then, as `claude`, runs Python, builds a Go program and
runs a real rootless podman container. It also exercises the gateway: an allowed host and its DNS work; a non-listed host,
an IP literal, port 22 and the podman subuid range are blocked; plain HTTP to a non-listed `Host` gets a 403; and root is
unaffected.

Not covered by CI, because it needs a logged-in Claude: the sign-in and the Remote Control session (and that it still
reaches Anthropic through the gateway), the sandbox's network allowlist and the `SessionStart` hook inside a live session. The nightly upgrade also needs the image to be
pullable without credentials, which this VM does not have.
