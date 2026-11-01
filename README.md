# homeserver-bootc

Fedora bootc (`fedora-bootc:44`) images for a home server, built and published by GitHub Actions. Full bootc docs: <https://bootc-dev.github.io/bootc/>

## Images

| Containerfile | Description |
| --- | --- |
| `homeserver.containerfile` | Headless home server |
| `homeserver-gui.containerfile` | Home server with GUI |
| `claude-vm.containerfile` | VM that runs Claude Code Remote Control, with no secrets baked in |

## Layout

- `build_files/` – build scripts (base, core, gui, post, ...)
- `system_files/` – files copied into the images
- `tests/` – image verification scripts
- `.github/workflows/` – build, lint, cleanup and Renovate pipelines

## Filesystem notes

- `/usr` is read-only and managed by the image; prefer it for config.
- `/etc` is editable. Locally modified files drift and stop receiving updates. List them with `ostree admin config-diff`, and revert one by copying it from `/usr/etc`.
- `/var` is only populated on first boot.

## Remote access

```sh
# ~/.ssh/config
Host portableinfo.pinggy
  HostName portableinfo.a.pinggy.link
  User cthtrifork
  Port 21412
  SetEnv TERM=xterm-256color
```

```sh
ssh -J portableinfo.pinggy cthtrifork@192.168.1.136
```

## Secrets (sops + age)

```sh
sops --encrypt --age "$AGE_PUB" plain > encrypted.sops
SOPS_AGE_KEY_FILE=/var/lib/sops/age/keys.txt sops -d encrypted.sops > plain
```

## Claude VM

`claude-vm.containerfile` builds `claude-vm-bootc`: a minimal VM that runs
[`claude remote-control`](https://code.claude.com/docs/en/remote-control) as the unprivileged user `claude`, so you can
drive it from claude.ai/code or the Claude app. Layout mirrors the home server: `system_files/claude-vm/`, numbered
`/etc/tmpfiles.d/` files and `tests/claude-vm/`.

### What is in it

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

### First-boot setup (once per VM)

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

### Security model

- **Policy:** `/etc/claude-code/managed-settings.json` is root-owned and has the highest precedence, so `claude`
  cannot change it. It rejects `--dangerously-skip-permissions` and runs only managed hooks (`allowManagedHooksOnly`),
  so hooks in repositories Claude clones are ignored ([managed settings](https://code.claude.com/docs/en/managed-settings.md)).
- **Bash sandbox:** Claude Code's built-in sandbox is required and cannot be bypassed by the model
  ([sandboxing](https://code.claude.com/docs/en/sandboxing.md)). Shell commands run in `bubblewrap`, can write only to
  `~/workspace`, `~/.npm-global`, `~/.npm`, `~/.local`, `~/.cache` and `~/go`, and can reach only the hosts in
  `allowedDomains`; any other host prompts. `~/.claude/.credentials.json` is hidden from them. Because commands are
  confined they run without a prompt (`autoAllowBashIfSandboxed`); set it to `false` to be asked every time.
  - **`podman *` is excluded:** rootless podman cannot run inside the sandbox. Podman still asks for approval, but once
    approved it and its containers are unconfined, with no network filter.
  - It is a guardrail, not a hard boundary: the proxy filters by hostname without inspecting TLS, broad hosts such as
    `github.com` can carry data out, and MCP servers and hooks are not covered.
  - The service omits `ProtectKernelTunables`, because it stops bubblewrap mounting its own `/proc`.
- **A Remote Control session is a shell as `claude`.** Whoever controls your claude.ai session controls the VM. Turn on
  **Require trusted devices** in your account settings (beta) ([docs](https://code.claude.com/docs/en/remote-control.md#trusted-devices)).
- **GitHub token:** use a fine-grained token limited to the repositories Claude should touch, with only the
  permissions it needs (typically Contents and Pull requests read/write) and a short expiry.
- **Data and terms:** while connected, the session transcript is stored on Anthropic's servers
  ([connection and security](https://code.claude.com/docs/en/remote-control.md#connection-and-security)). Use your own
  login and do not share it ([legal](https://code.claude.com/docs/en/legal-and-compliance.md)). Do not set
  `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC`: it also disables Remote Control.

### Operating notes

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

### Build and test

`create-vmdk-image.yaml` accepts `claude-vm-bootc`. Locally:

```sh
sudo podman run --rm -it --privileged -v ./out:/output -v ./config.toml:/config.toml:ro \
  quay.io/centos-bootc/bootc-image-builder:latest --type qcow2 --config /config.toml \
  ghcr.io/cthtrifork/homeserver-bootc/claude-vm-bootc:latest
```

CI builds it like the other images (`claude-vm` in the build matrix). The `e2e` label boots it in QEMU and runs
`tests/claude-vm/`.

## Local build test

```sh
echo "" > /tmp/PINGGY_TOKEN
echo "${GITHUB_TOKEN}" > /tmp/REGISTRY_TOKEN
cp "${HOME}/.docker/config.json" /tmp/creds
echo "${SOPS_AGE_KEY}" > /tmp/AGE_KEY
mkdir -p /tmp/runner/.cache/dnf /tmp/runner/.cache/tmp

podman build \
  --network=slirp4netns:enable_ipv6=false \
  -f homeserver-gui.containerfile \
  --build-arg REGISTRY_USERNAME="caspertdk" \
  --build-arg REGISTRY_URL=ghcr.io \
  --build-arg PINGGY_HOST="test.com" \
  --build-arg REPOSITORY="https://github.com/cthtrifork/homeserver-bootc" \
  --secret id=registry_token,src=/tmp/REGISTRY_TOKEN \
  --secret id=pinggy_token,src=/tmp/PINGGY_TOKEN \
  --secret id=creds,src=/tmp/creds \
  --secret id=agekey,src=/tmp/AGE_KEY \
  -v /tmp/runner/.cache/dnf:/var/cache/libdnf5:z \
  -v /tmp/runner/.cache/tmp:/runner/cache:z
```

See also: [Using toolbox to inspect bootc containers](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/9/html/using_image_mode_for_rhel_to_build_deploy_and_manage_operating_systems/managing-rhel-bootc-images#using-toolbx-to-inspect-bootc-containers_managing-rhel-bootc-images)
