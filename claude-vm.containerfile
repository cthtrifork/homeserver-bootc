# syntax=docker/dockerfile:1.29@sha256:572cebbc2b15e6f84c077742952674889cb63cd5e9b80abdffcbe587b6f19183
# Minimal bootc VM running `claude remote-control`; contains no secrets.
FROM quay.io/fedora/fedora-bootc:45 AS base

# Build context for the helper scripts (same pattern as homeserver.containerfile)
FROM scratch AS ctx_build
COPY build_files/ /build_files/

FROM base AS final

ARG CLAUDE_CODE_VERSION=2.1.332 # renovate: datasource=npm depName=@anthropic-ai/claude-code
ARG PLAYWRIGHT_VERSION=1.65.1 # renovate: datasource=npm depName=playwright
ARG LIGHTHOUSE_VERSION=13.6.0 # renovate: datasource=npm depName=lighthouse

# Tooling Claude can use: bash, python (+pip), node (+npm), go, make, rootless podman (+ podman-compose, the provider behind
# `podman compose`), plus linters/formatters
# (ShellCheck, yamllint, jq/yq; shfmt, hadolint and actionlint are installed below).
# bubblewrap + socat are what Claude Code's Bash sandbox needs on Linux; passt gives rootless podman its networking
# (weak dependencies are off); tree is used by tests/diagnostics.sh. nftables + dnsmasq + iron-proxy (allowlist, swaps in the GitHub token) make up the
# egress allowlist gateway for the agent user (see docs/claude-vm/README.md).
# Node 24 (the Active LTS line, packaged by Fedora as the parallel-installable nodejs24): nodejs24-bin and nodejs24-npm-bin are
# the packages that provide /usr/bin/node, npm and npx (via alternatives); the plain nodejs/nodejs22 packages are not installed.
# nodejs24-full-i18n: Fedora builds Node with small ICU, which has no break-iterator data, so without this package any
# `new Intl.Segmenter()` segfaults (Lighthouse's "Minify CSS" audit hit it); it puts the full ICU data in
# /usr/share/node-24/icudata, where Node looks. tests/claude-vm/system-test.sh checks it.
# ffmpeg-free: Fedora's ffmpeg (VP8/VP9, Opus, AAC, MJPEG, PNG; no x264/x265 encoders). The full RPM Fusion ffmpeg of the GUI
# image is not used: it needs a third-party repo and extra egress hosts at build time only, but gives Claude little more.
# Fedora RPMs follow the base image (quay.io/fedora/fedora-bootc, bumped by Renovate).
# Repo host, pinned instead of the metalink; keep in step with the arc-runner egress policy in talos-gitops.
ARG FEDORA_MIRROR=https://dl.fedoraproject.org/pub/fedora
RUN mkdir -p /etc/dnf/repos.override.d && printf '%s\n' \
      '[fedora]' 'metalink=' "baseurl=${FEDORA_MIRROR}/linux/releases/\$releasever/Everything/\$basearch/os/" \
      '[updates]' 'metalink=' "baseurl=${FEDORA_MIRROR}/linux/updates/\$releasever/Everything/\$basearch/" \
      '[updates-archive]' 'enabled=0' \
    > /etc/dnf/repos.override.d/50-mirror.repo

RUN dnf -y install --setopt=install_weak_deps=False \
        bash python3 python3-pip nodejs24 nodejs24-bin nodejs24-npm nodejs24-npm-bin nodejs24-full-i18n golang podman podman-remote podman-compose shadow-utils fuse-overlayfs acl \
        openssh-clients bubblewrap socat skopeo passt git-core gh jq yq ShellCheck yamllint make ripgrep tmux tree cloc qemu-guest-agent cloud-init \
        nftables dnsmasq \
        chromium ffmpeg-free \
    && dnf clean all \
    && rm -f /etc/dnf/repos.override.d/50-mirror.repo

# cloud-init ships a drop-in that stops sshd-keygen whenever cloud-init is active, expecting cloud-init's own ssh module to make the
# host keys. That module is not used here (see 90-claude-vm.cfg), so without this a VM with a cidata disk would boot with no host keys.
RUN find /usr/lib/systemd/system -name disable-sshd-keygen-if-cloud-init-active.conf -delete

# Rootless podman runs as separate UIDs, not as the agents: claude-podman (1200) and claude-rc-personal-podman (1201, see
# sysusers.d). The agents get no subuid range, so they cannot start a user namespace of their own, and /usr/bin/podman is
# only executable for group claude-podman-exec (GID 1210, by number because sysusers has not run yet); they use the wrapper in
# /usr/libexec/claude-vm/bin, which talks to their podman user's API socket through podman-remote.
RUN echo "claude-podman:100000:65536" >> /etc/subuid && echo "claude-podman:100000:65536" >> /etc/subgid
RUN echo "claude-rc-personal-podman:165536:65536" >> /etc/subuid && echo "claude-rc-personal-podman:165536:65536" >> /etc/subgid
RUN chgrp 1210 /usr/bin/podman && chmod 0750 /usr/bin/podman

# crane, hadolint, actionlint, shfmt, kubectl, helm, kustomize, kubeconform, flux-schema (not packaged in Fedora 45): pinned release binaries, checksum-verified. Versions live in
# build_files/claude-vm-utilities.sh (Renovate `# renovate:` comments); downloads are kept in the CI runner cache.
RUN --mount=type=bind,from=ctx_build,src=/,dst=/ctx \
    /ctx/build_files/claude-vm-utilities.sh

# Installed after the pinned binaries above: Claude Code is bumped most often, so this keeps their layers cached.
# Claude Code lives under /usr so it is part of the immutable image and is
# upgraded by bootc, not by an in-place auto-updater.
# /root is a dangling symlink to /var/roothome while building, so npm's default cache/log dir
# (~/.npm) cannot be created; keep both in /tmp and remove them again.
RUN npm_config_cache=/tmp/npm-cache npm_config_logs_dir=/tmp/npm-cache/_logs \
        npm install --global --prefix /usr "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}" \
    && rm -rf /tmp/npm-cache \
    && claude --version

# Playwright (browser automation / screenshots). The library lives under /usr like Claude Code; the browser is Fedora's
# chromium RPM (Playwright's own download is not supported on Fedora), so no browser download happens at build or run
# time. Scripts must launch it with executablePath /usr/bin/chromium-browser and --no-sandbox (Chromium's own sandbox
# cannot nest inside bubblewrap); /etc/profile.d/81-claude-playwright.sh exports the matching env vars.
RUN PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 npm_config_cache=/tmp/npm-cache npm_config_logs_dir=/tmp/npm-cache/_logs \
        npm install --global --prefix /usr "playwright@${PLAYWRIGHT_VERSION}" \
    && rm -rf /tmp/npm-cache

# Lighthouse (page audits). Installed under /usr like Claude Code and Playwright; it drives Fedora's chromium RPM through
# CHROME_PATH (exported by /etc/profile.d/81-claude-playwright.sh), and Chrome must be started with --no-sandbox inside bubblewrap
# (`lighthouse <url> --chrome-flags="--headless=new --no-sandbox"`).
RUN npm_config_cache=/tmp/npm-cache npm_config_logs_dir=/tmp/npm-cache/_logs \
        npm install --global --prefix /usr "lighthouse@${LIGHTHOUSE_VERSION}" \
    && rm -rf /tmp/npm-cache \
    && lighthouse --version

# Playwright's own ffmpeg (a small build that encodes VP9 .webm, not a browser): `recordVideo` writes through it and fails without it
# ("Video rendering requires ffmpeg binary"). Downloaded at build time only (the VM's egress gateway blocks Playwright's CDN) into
# a path under /usr that /etc/profile.d/81-claude-playwright.sh exports as PLAYWRIGHT_BROWSERS_PATH.
RUN PLAYWRIGHT_BROWSERS_PATH=/usr/share/claude-vm/ms-playwright playwright install ffmpeg \
    && chmod -R a+rX /usr/share/claude-vm/ms-playwright

RUN ln -sf /usr/share/zoneinfo/Europe/Copenhagen /etc/localtime

# key-only SSH admin user (caspertdk, see sysusers.d) gets sudo, like the homeserver image
RUN echo "%wheel        ALL=(ALL)       NOPASSWD: ALL" > /etc/sudoers.d/wheel-sudo \
    && chmod 0440 /etc/sudoers.d/wheel-sudo

# Same public keys as the homeserver image (one source of truth), applied by /etc/tmpfiles.d/11-caspertdk-ssh.conf
COPY --chmod=0644 system_files/homeserver/usr/share/homeserver/authorized_keys.pub /usr/share/claude-vm/authorized_keys.pub

COPY system_files/claude-vm/ /

# The VM refuses an unsigned image of ours: the public key of the OS image signatures and the policy that requires it,
# the same files as the homeserver images (docs/signing.md)
COPY --chmod=0644 cosign.pub /etc/pki/cosign/cosign.pub
COPY --chmod=0644 policy.json /etc/containers/policy.json
COPY --chmod=0644 system_files/homeserver/etc/containers/registries.d/ghcr.yaml /etc/containers/registries.d/ghcr.yaml
RUN chmod 0755 /usr/bin/claude-vm-seed-github-app /usr/bin/claude-vm-signing-key /usr/bin/claude-vm-ssh-address /usr/bin/claude-vm-egress /usr/libexec/claude-vm/* \
    && systemctl enable claude-remote-control.service qemu-guest-agent.service bootc-fetch-apply-updates.timer \
        claude-vm-egress-nft.service claude-vm-egress-ca.service claude-vm-egress-proxy.service claude-vm-egress-proxy@claude.service claude-vm-egress-proxy@claude-rc-personal.service claude-vm-egress-proxy@containers.service claude-vm-egress-dns.service \
        claude-vm-podman@claude.service claude-vm-upgrade-poll.timer claude-vm-upgrade-check.timer

# var-tmpfiles is skipped: CI bind-mounts the runner's dnf cache at /var/cache/libdnf5 (owned by the
# runner UID, which does not exist in the image), which that lint reports as an unknown user.
RUN bootc container lint --skip var-tmpfiles
