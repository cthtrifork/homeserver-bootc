# syntax=docker/dockerfile:1.22@sha256:4a43a54dd1fedceb30ba47e76cfcf2b47304f4161c0caeac2db1c61804ea3c91
# Minimal bootc VM running `claude remote-control`; contains no secrets.
FROM quay.io/fedora/fedora-bootc:44 AS base

# Build context for the helper scripts (same pattern as homeserver.containerfile)
FROM scratch AS ctx_build
COPY build_files/ /build_files/

FROM base AS final

ARG CLAUDE_CODE_VERSION=2.1.318 # renovate: datasource=npm depName=@anthropic-ai/claude-code
ARG PLAYWRIGHT_VERSION=1.65.0 # renovate: datasource=npm depName=playwright

# Tooling Claude can use: bash, python (+pip), node (+npm), go, make, rootless podman (+ podman-compose, the provider behind
# `podman compose`), plus linters/formatters
# (ShellCheck, shfmt, yamllint, jq/yq; hadolint and actionlint are installed below).
# bubblewrap + socat are what Claude Code's Bash sandbox needs on Linux; passt gives rootless podman its networking
# (weak dependencies are off); tree is used by tests/diagnostics.sh. nftables + nginx (stream/SNI) + dnsmasq make up the
# egress allowlist gateway for the agent user (see docs/claude-vm/README.md).
# nodejs-full-i18n (an alias of nodejs22-full-i18n, pinned to the same nodejs22 build): Fedora builds Node with small ICU, which has no
# break-iterator data, so without this package any `new Intl.Segmenter()` segfaults (Lighthouse's "Minify CSS" audit hit it); it puts
# icudt78l.dat in /usr/share/node-22/icudata, where Node looks. tests/claude-vm/system-test.sh checks it.
# ffmpeg-free: Fedora's ffmpeg (VP8/VP9, Opus, AAC, MJPEG, PNG; no x264/x265 encoders). The full RPM Fusion ffmpeg of the GUI
# image is not used: it needs a third-party repo and extra egress hosts at build time only, but gives Claude little more.
# Fedora RPMs follow the base image (quay.io/fedora/fedora-bootc, bumped by Renovate).
RUN dnf -y install --setopt=install_weak_deps=False \
        bash python3 python3-pip nodejs nodejs-full-i18n npm golang podman podman-compose shadow-utils fuse-overlayfs \
        openssh-clients bubblewrap socat skopeo passt git-core gh jq yq ShellCheck shfmt yamllint make ripgrep tmux tree cloc qemu-guest-agent \
        nftables nginx nginx-mod-stream dnsmasq \
        chromium ffmpeg-free \
    && dnf clean all

# Rootless podman for the service users (claude, UID 1100; claude-rc-personal, UID 1101; see sysusers.d)
RUN echo "claude:100000:65536" >> /etc/subuid && echo "claude:100000:65536" >> /etc/subgid
RUN echo "claude-rc-personal:165536:65536" >> /etc/subuid && echo "claude-rc-personal:165536:65536" >> /etc/subgid

# crane, hadolint, actionlint (not packaged in Fedora): pinned release binaries, checksum-verified. Versions live in
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
# Egress allowlist: validate it (fails the build on a bad entry) and derive the sandbox's allowedDomains and the
# gateway's nginx/dnsmasq lists from the one source file.
RUN --mount=type=bind,from=ctx_build,src=/,dst=/ctx \
    python3 /ctx/build_files/claude-vm/egress_allowlist.py /ctx/build_files/claude-vm/egress-allowlist.txt \
        /etc/claude-code/managed-settings.json /usr/share/claude-vm/egress

# The egress proxy runs from a copy of nginx under /usr/libexec (bin_t -> unconfined_service_t, like the other
# claude-vm helpers). The packaged binary runs in httpd_t, which SELinux does not let connect to upstream servers
# (avc: denied { name_connect } ... tcontext=http_port_t) unless httpd_can_network_connect is on, which allows all ports.
RUN install -m 0755 /usr/sbin/nginx /usr/libexec/claude-vm/egress-proxy

# Podman API socket for the claude user (socket-activated, /run/user/1100/podman/podman.sock). Enabled for all user
# managers (`--global` writes /etc/systemd/user/sockets.target.wants): ~/.config/systemd is write-protected for claude.
RUN systemctl --global enable podman.socket

RUN chmod 0755 /usr/bin/claude-vm-seed-github-app /usr/bin/claude-vm-signing-key /usr/bin/claude-vm-ssh-address /usr/bin/claude-vm-egress /usr/libexec/claude-vm/* \
    && systemctl enable claude-remote-control.service qemu-guest-agent.service bootc-fetch-apply-updates.timer \
        claude-vm-egress-nft.service claude-vm-egress-proxy.service claude-vm-egress-dns.service

# var-tmpfiles is skipped: CI bind-mounts the runner's dnf cache at /var/cache/libdnf5 (owned by the
# runner UID, which does not exist in the image), which that lint reports as an unknown user.
RUN bootc container lint --skip var-tmpfiles
