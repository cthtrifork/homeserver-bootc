# claude-vm

Back to the [main README](../../README.md).

`claude-vm.containerfile` builds `claude-vm-bootc`: a minimal VM that runs
[`claude remote-control`](https://code.claude.com/docs/en/remote-control) as an unprivileged user, so you can drive it from
claude.ai/code or the Claude app. Layout mirrors the home server: `system_files/claude-vm/`, numbered `/etc/tmpfiles.d/`
files and `tests/claude-vm/`.

## Key files

- [Managed settings](../../system_files/claude-vm/etc/claude-code/managed-settings.json): root-owned policy shipped to `/etc/claude-code/`
- [Egress allowlist](../../build_files/claude-vm/egress-allowlist.txt): the one list of hosts the agent users may reach
- [AGENTS.md](../../system_files/claude-vm/etc/claude-code/AGENTS.md): guidelines and installed tools for the agent

## Overview

```mermaid
flowchart LR
    REG[("ghcr.io image")]
    YOU["You<br/>claude.ai / app"]
    ANTH["claude.ai"]
    GH["GitHub"]

    subgraph VM["Claude VM"]
        SETUP["Manual setup:<br/>GitHub App + Claude login<br/>(per agent user)"]
        RC["claude remote-control<br/>(one service per agent user)"]
        SB["Sandboxed shell<br/>limited paths + domains"]
        POD["Rootless podman<br/>(approved commands)"]
        GW["Egress gateway<br/>nftables + nginx + dnsmasq<br/>domain allowlist"]
        TOK["Token refresher<br/>(root, 30 min, per-user App)"]
        UPD["03:00: bootc upgrade --apply<br/>(reboots if new image)"]
        SSH["SSH<br/>(caspertdk, public keys only)"]
    end

    REG -->|install / pull| VM
    SETUP --> RC
    TOK -->|"1h token"| RC
    RC --> SB
    RC --> POD
    SB --> GW
    POD --> GW
    RC <--> GW
    GW --> GH
    GW <--> ANTH
    ANTH <--> YOU
    REG --> UPD
    YOU -.->|"optional Pinggy tunnel"| SSH
```

- **No secrets in the image.** GitHub App keys and Claude logins are seeded by hand on the VM. SSH host keys are generated at first boot.
- **Agent users.** Each runs its own Remote Control service, with its own home, claude.ai login, podman storage, GitHub App and token.
  Nothing is shared between them except the egress gateway.

  | Claude login | Unix user | Service | Session name |
  |---|---|---|---|
  | main | `claude` (1100) | `claude-remote-control` | `<hostname>` |
  | personal (opt-in) | `claude-rc-personal` (1101) | `claude-remote-control-rc-personal` | `<hostname>-rc-personal` |

  Each service has its own memory/CPU caps (percent of VM RAM; see the unit files), so size the VM for the sum
  (2 vCPU / 4 GB light use, 4-8 vCPU / 8-16 GB for parallel builds, 30 GB+ disk for podman). Override with a drop-in in
  `/etc/systemd/system/<service>.d/`.
- **SSH:** key-only for `caspertdk` (sudo), using the same public keys as the home server. The agent users have no sudo.
- **Updates:** `bootc-fetch-apply-updates.timer` runs `bootc upgrade --apply` at 03:00, so a new image reboots the VM and ends
  running sessions (Remote Control brings them back for about four hours). Drop `--apply` in
  `bootc-fetch-apply-updates.service.d/override.conf` to only stage.
- **Versions:** Claude Code and Playwright are pinned by `ARG ... # renovate:` lines in the containerfile, crane, hadolint and
  actionlint in `build_files/claude-vm-utilities.sh`. The rest is Fedora packages.

## First-boot setup (once per VM, per agent user)

```sh
ssh caspertdk@<vm>

# 1. Seed that user's GitHub App (see "GitHub access"). The key is read from a file or stdin, never an argument.
sudo claude-vm-seed-github-app claude <app-id> <installation-id> ./app-private-key.pem

# 2. Create the commit-signing key and print its public key (see "Signed commits"; `claude` only)
sudo claude-vm-signing-key

# 3. Sign in as the agent user. Remote Control needs a claude.ai login (API keys are not supported).
sudo -iu claude
cd ~/workspace && claude          # /login, trust the folder, then exit
claude remote-control             # answer 'y' to "Enable Remote Control?", then Ctrl-C
exit

# 4. Start the service (enabled, but idle until steps 1 and 3 are done)
sudo systemctl restart claude-remote-control
journalctl -u claude-remote-control -f     # shows the session URL
```

For `claude-rc-personal`, repeat steps 1 and 3 with that user, then `sudo systemctl enable --now claude-remote-control-rc-personal`.
It stays inert until `~/.claude/.credentials.json` exists. Its `~/.gitconfig` turns commit signing off; set your own
`user.name`/`user.email` (and a signing key) there.

Rotate an App key by re-running step 1. Claude logins live in `~/.claude/` and survive upgrades.

## GitHub access

Each agent user acts as its own GitHub App (a bot), not as a person with a personal token, so repositories and permissions
can differ per user. An App's private key lives only in `/etc/claude-vm/github-app/<user>/` (root, 0600). The template
units `claude-vm-github-token@<user>.timer` and `.service` run `refresh-github-token <user>` as root every 30 minutes (and at
boot): it signs a JWT, trades it for a one-hour installation token and writes it to `/run/claude-vm/<user>/github-token`
(0640 root:`<user>`, tmpfs). Nothing holds the token in an environment variable: the `gh` wrapper in
`/usr/libexec/claude-vm/bin` (first on the service's `PATH`, and the git credential helper in `/etc/gitconfig`) reads the
calling user's token file on every call. A user cannot read another user's token or any private key.

Create an App per user:

1. GitHub > Settings > Developer settings > GitHub Apps > New. Repository permissions: **Contents** and **Pull requests**
   read/write, **Metadata** read; add **Actions** read to read workflow runs. Leave the rest off (without **Workflows** it
   cannot change `.github/workflows/`). Untick "Webhook active". Never make it a bypass actor in a ruleset.
2. Generate a private key, install the App only on the repositories that user should touch, and note the **App ID** and
   the **installation ID** (the number at the end of `https://github.com/settings/installations/<id>`).
3. `sudo claude-vm-seed-github-app <user> <app-id> <installation-id> ./key.pem`, then delete the `.pem`.

The token carries the App's permissions on every repository it is installed on, so narrow them in the App's settings.
Check with `journalctl -u claude-vm-github-token@<user>` and `sudo -u <user> gh api /installation/repositories`.

## Signed commits

`/etc/gitconfig` signs every commit and tag of `claude` with an SSH key made on the VM by `sudo claude-vm-signing-key`
(`--rotate` replaces it). The key is `/var/home/claude/.ssh/claude_signing`, has no passphrase, and until it exists commits
fail rather than going out unsigned. GitHub shows "Verified" only if the commit email is verified on the account holding the key.

1. Add the key printed by `claude-vm-signing-key` to your GitHub account as a **Signing Key** (Settings > SSH and GPG keys).
2. Set a commit email verified on your account (your `<id>+<username>@users.noreply.github.com` address works). `claude`
   cannot edit `~/.gitconfig`, so as `caspertdk`, from a directory `claude` can read:

   ```sh
   cd /var/home/claude && sudo -u claude git config --file /var/home/claude/.gitconfig user.email "<your-verified-email>"
   sudo claude-vm-signing-key    # refreshes ~/.ssh/allowed_signers
   ```

Commits are attributed to you and the key signs as you, so if it leaks, delete it on GitHub and run `--rotate`.

## SSH over a free Pinggy tunnel (opt-in)

`claude-pinggy.service` opens an account-less [Pinggy](https://pinggy.io/docs/run_tunnel_on_startup/linux/) TCP tunnel to
sshd, so you can log in without knowing the VM's IP. It ships disabled: `sudo systemctl enable --now claude-pinggy`.

```sh
claude-vm-ssh-address        # on the VM; or ask Claude, or type /ssh-address
ssh -p 41234 caspertdk@abcde-1-2-3-4.a.free.pinggy.link
```

The address changes whenever the tunnel restarts (free tunnels last about 60 minutes). The sshd is then on the internet:
password login is off and only the keys in `authorized_keys.pub` work, but disable it when unused
(`sudo systemctl disable --now claude-pinggy`).

## Security model

- **Policy:** `/etc/claude-code/managed-settings.json` has the highest precedence and `claude` cannot change it. Sessions start
  in bypass-permissions mode; the sandbox, deny rules and egress gateway are the limits. Only managed hooks run
  (`allowManagedHooksOnly`), so hooks in cloned repositories are ignored. Keys and values are documented by
  [managed settings](https://code.claude.com/docs/en/managed-settings.md); changes to this file are in git.
- **Bash sandbox:** required (`bubblewrap`), writes only to `~/workspace`, `~/.npm-global`, `~/.npm`, `~/.local`, `~/.cache`
  and `~/go`, reaches only the allowlisted hosts, and cannot read `~/.claude/.credentials.json`. `podman` and `podman-compose`
  are excluded (rootless podman cannot run inside it) and keep only the egress gateway's network confinement. The podman API
  socket is deliberately not exposed to the sandbox. It is a guardrail, not a hard boundary: the proxy filters by hostname,
  broad hosts such as `github.com` can carry data out, and MCP servers and hooks are not covered.
- **A Remote Control session is a shell as the agent user.** Whoever controls your claude.ai session controls the VM. Turn on
  [Require trusted devices](https://code.claude.com/docs/en/remote-control.md#trusted-devices).
- **GitHub Apps:** install each only on the repositories its user should touch. The agent holds a one-hour token, never the key.
- **Data and terms:** the session transcript is stored on Anthropic's servers while connected. Use your own login and do
  not share it. Do not set `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC`: it also disables Remote Control.

## Usage telemetry

Claude Code sends OpenTelemetry metrics (tokens, cost, sessions, lines of code, commits, pull requests, active time) to the OTLP
receiver of the cluster's Prometheus ([talos-gitops `k8s/apps/claude-system`](https://github.com/cthtrifork/talos-gitops/tree/main/k8s/apps/claude-system#usage-telemetry)),
tagged `environment=claude-vm`. Both agent users send; the managed settings carry the whole configuration.

- **Endpoint:** `http://otel.portableinfo.cloud/api/v1/otlp` (port 80, `http/protobuf`), a Cloudflare A record to a private LAN
  address of the cluster. Claude Code appends `/v1/metrics`. No ingress and no new egress rule: `portableinfo.cloud` is already on the
  allowlist and the gateway forwards plain HTTP by `Host`. The name must resolve to the private address through the VM's resolver:
  if that resolver filters private answers for public names (DNS rebinding protection), exports fail with a DNS error in the Claude Code log.
- **Auth:** none. The endpoint is LAN-only and the cluster's network policy limits who can reach it.
- **Temporality:** delta, set explicitly; Prometheus turns it into cumulative counters.

Look at the result in Prometheus (`claude_code_*{environment="claude-vm"}`) or on the usage page of the cluster.

## Egress gateway

Everything the agent users start, including rootless podman containers, reaches only hosts on one allowlist, enforced in the
kernel by UID (`claude`, `claude-rc-personal` and the podman subuid ranges), independent of the sandbox.

| Unit | What it does |
| --- | --- |
| `claude-vm-egress-nft` | nftables: redirects DNS to dnsmasq and HTTPS/HTTP to nginx, rejects everything else (QUIC, SSH, other ports, IPv6) |
| `claude-vm-egress-proxy` | nginx, no TLS interception: reads the SNI (or HTTP `Host`) and drops unlisted names and IP literals |
| `claude-vm-egress-dns` | dnsmasq: resolves only allowlisted domains |

Root, `caspertdk`, `bootc upgrade`, dnf and the Pinggy tunnel are not restricted. The remote-control services require all three
units. SELinux is enforcing, which is why nginx runs from a copy under `/usr/libexec/claude-vm/`, and systemd-resolved's
varlink socket is root-only so `nss-resolve` cannot bypass the DNS filter.

**One allowlist.** `build_files/claude-vm/egress-allowlist.txt` has one domain per line (subdomains included).
`egress_allowlist.py` fails the image build on an invalid, duplicate or redundant entry and derives the sandbox's
`allowedDomains` and the nginx and dnsmasq maps from it. To allow another host, add it and rebuild.

**What a block looks like.** Usually "could not resolve host"; a listed name blocked at the proxy shows as a connection reset
(HTTPS) or a 403 (HTTP). SSH and git-over-SSH are blocked; use HTTPS remotes. `sudo claude-vm-egress blocked` summarises
blocked requests since boot (`--raw` plus any `journalctl` argument for each one), `claude-vm-egress allowed` prints the list.

Filtering is by name, not content: a listed shared CDN or broad service can still carry data out.

## Operating notes

- systemd restarts the services (`Restart=always`); an unreachable VM shows as an offline session at claude.ai/code. For push
  notifications, run `/config` once in an interactive `claude` as the agent user.
- `/var` and `/etc` are not re-applied on upgrade (tmpfiles `C` never overwrites). Revoking a key in a later image does not
  reach VMs that already booted: edit `~caspertdk/.ssh/authorized_keys` there. Keep local policy changes in
  `/etc/claude-code/managed-settings.d/*.json`; list drift with `ostree admin config-diff`.
- Give parallel agents separate git worktrees. Rootless podman containers may escape the unit's cgroup limits; cap them with
  `podman run --memory/--cpus`.

## Build a disk image

`create-vmdk-image.yaml` accepts `claude-vm-bootc`; CI builds it with the other images. Locally:

```sh
sudo podman run --rm -it --privileged -v ./out:/output -v ./config.toml:/config.toml:ro \
  quay.io/centos-bootc/bootc-image-builder:latest --type qcow2 --config /config.toml \
  ghcr.io/cthtrifork/homeserver-bootc/claude-vm-bootc:latest
```

## Tests

`tests/claude-vm/` runs in QEMU when a non-draft pull request has the `e2e` label: tools, idle services, policy, users, home
and token directory permissions, no baked-in keys, the seed helper, rootless podman, and the egress gateway (also from inside
podman containers). Not covered, because it needs a logged-in Claude: sign-in, the Remote Control session, and the sandbox
and `SessionStart` hook in a live session.
