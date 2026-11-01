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

## Security model

- **Policy:** `/etc/claude-code/managed-settings.json` is root-owned and has the highest precedence, so `claude`
  cannot change it. It rejects `--dangerously-skip-permissions` and runs only managed hooks (`allowManagedHooksOnly`),
  so hooks in repositories Claude clones are ignored ([managed settings](https://code.claude.com/docs/en/managed-settings.md)).
- **Bash sandbox:** Claude Code's built-in sandbox is required and cannot be bypassed by the model
  ([sandboxing](https://code.claude.com/docs/en/sandboxing.md)). Shell commands run in `bubblewrap`, can write only to
  `~/workspace`, `~/.npm-global`, `~/.npm`, `~/.local`, `~/.cache` and `~/go`, and can reach only the hosts in
  `allowedDomains`; any other host prompts. `~/.claude/.credentials.json` is hidden from them. Because commands are
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

- **`claude-vm-egress-nft`** (`/usr/share/claude-vm/egress.nft`): for UID 1100 and the podman subuid range
  (100000-165535, which host-network containers run as), redirects DNS to `:5353`, HTTPS to `:3129` and HTTP to `:3128`
  on loopback and rejects everything else (QUIC/UDP, SSH, other ports, IPv6). rootless podman's `pasta` opens its sockets
  as `claude`, so container traffic is matched too. Root, `caspertdk`, `bootc upgrade` and dnf are **not** restricted.
- **`claude-vm-egress-proxy`** (nginx, no TLS interception): reads the SNI of a TLS handshake (or the HTTP `Host`) and
  connects to that name itself; unlisted names are dropped (403 for HTTP). An IP address with no SNI is dropped.
- **`claude-vm-egress-dns`** (dnsmasq): forwards only allowlisted domains to the system resolver and refuses the rest.
- **One allowlist:** `sandbox.network.allowedDomains` in the managed settings, plus
  `/usr/share/claude-vm/egress-extra.txt` (the Anthropic endpoints Remote Control needs) and local additions in
  `/etc/claude-vm/egress-extra.d/*.txt` (one domain per line; a domain also covers its subdomains, and `*.` is optional).
  `claude-vm-egress-generate` normalizes and validates them on each start (invalid entries are reported and skipped, an
  empty list is an error) and writes `/run/claude-vm/egress/{allow.txt,nginx-allow.map,dnsmasq-servers}`, which the static
  nginx and dnsmasq configs in `/usr/share/claude-vm/` include.
- `claude-remote-control` requires all three units. Without them it does not start, and the user has no network anyway.

To allow another host (also needed after approving a sandbox prompt for it, because the gateway is stricter than the
prompt):

```sh
echo example.org | sudo tee -a /etc/claude-vm/egress-extra.d/local.txt
sudo systemctl restart claude-vm-egress-generate claude-vm-egress-proxy claude-vm-egress-dns
```

Limits: filtering is by name, not content. A listed host that is a shared CDN or a broad service (`github.com`, `ghcr.io`,
`pypi.org`) can still carry data out, domain fronting to a listed CDN is possible, and DNS queries for listed domains
can carry data. Plain SSH and git-over-SSH are blocked; use HTTPS remotes. Blocked requests show up as connection
resets or DNS failures, not clear errors.

## Operating notes

- **Monitoring:** nothing extra is installed; the docs recommend none. systemd restarts the service
  (`Restart=always`). Server mode exits after about 10 minutes without network, and a restart in the same directory
  brings its sessions back for about four hours ([limitations](https://code.claude.com/docs/en/remote-control.md#limitations)).
  An unreachable VM shows as an offline session at claude.ai/code. For a push when a task finishes or needs a
  decision, run `/config` once in an interactive `claude` as `claude` and enable the push options
  ([push notifications](https://code.claude.com/docs/en/remote-control.md#mobile-push-notifications)).
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
| `sandbox.network.allowedDomains` | GitHub and ghcr.io, container registries, npm, PyPI, Go, Debian, a few docs and vulnerability-data hosts | the sandbox prompts for anything else; the [egress gateway](#egress-gateway) uses the same list |

## Tests

`tests/claude-vm/` runs in QEMU when a pull request has the `e2e` label. The system test checks the tools, that the
service is enabled but idle, the staged-update notice, the policy, that `bubblewrap` starts under the service's
hardening, users and SSH, home directories and lingering, and that no key or token file is on the VM. The user test
checks that the seed helper refuses a private key, then, as `claude`, runs Python, builds a Go program and runs a real
rootless podman container.

The user test also checks the egress gateway: an allowed host works and DNS, a non-listed host, an IP literal, port 22 and
the subuid range are blocked, and root is unaffected.

Not covered by CI, because it needs a logged-in Claude: the sign-in and the Remote Control session (and that it still
reaches Anthropic through the gateway), the sandbox's network allowlist and the `SessionStart` hook inside a live session. The nightly upgrade also needs the image to be
pullable without credentials, which this VM does not have.
