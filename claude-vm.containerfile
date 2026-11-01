# syntax=docker/dockerfile:1.22@sha256:4a43a54dd1fedceb30ba47e76cfcf2b47304f4161c0caeac2db1c61804ea3c91
#
# Minimal bootc VM image that runs `claude remote-control` as an unprivileged user.
#
# Deliberately contains NO secrets: no registry token, no age/sops key, no SSH or
# deploy keys, no GitHub token. The GitHub token is seeded by hand after first boot
# (see "Claude VM" in README.md), and Claude itself is signed in interactively.
FROM quay.io/fedora/fedora-bootc:44 AS base

FROM base AS final

ARG CLAUDE_CODE_VERSION=2.1.316 # renovate: datasource=npm depName=@anthropic-ai/claude-code
ARG CRANE_VERSION=v0.22.1 # renovate: datasource=github-releases packageName=google/go-containerregistry

# Tooling Claude can use: bash, python (+pip), node (+npm), go, rootless podman.
# bubblewrap + socat are what Claude Code's Bash sandbox needs on Linux; passt gives rootless podman its networking
# (weak dependencies are off); tree is used by tests/diagnostics.sh.
# Fedora RPMs follow the base image (quay.io/fedora/fedora-bootc, bumped by Renovate).
RUN dnf -y install --setopt=install_weak_deps=False \
        bash python3 python3-pip nodejs npm golang podman shadow-utils fuse-overlayfs \
        openssh-clients bubblewrap socat skopeo passt git-core gh jq ripgrep tmux tree qemu-guest-agent \
    && dnf clean all

# Rootless podman for the service user (claude, UID 1100; see sysusers.d)
RUN echo "claude:100000:65536" >> /etc/subuid && echo "claude:100000:65536" >> /etc/subgid

# Claude Code lives under /usr so it is part of the immutable image and is
# upgraded by bootc, not by an in-place auto-updater.
# /root is a dangling symlink to /var/roothome while building, so npm's default cache/log dir
# (~/.npm) cannot be created; keep both in /tmp and remove them again.
RUN npm_config_cache=/tmp/npm-cache npm_config_logs_dir=/tmp/npm-cache/_logs \
        npm install --global --prefix /usr "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}" \
    && rm -rf /tmp/npm-cache \
    && claude --version

# crane (not packaged in Fedora): pinned release, checksum-verified against the release's checksums.txt (amd64)
RUN set -eux; cd /tmp; \
    base="https://github.com/google/go-containerregistry/releases/download/${CRANE_VERSION}"; \
    curl -fsSL -O "${base}/go-containerregistry_Linux_x86_64.tar.gz" -O "${base}/checksums.txt"; \
    grep ' go-containerregistry_Linux_x86_64.tar.gz$' checksums.txt | sha256sum -c -; \
    tar -xzf go-containerregistry_Linux_x86_64.tar.gz -C /usr/bin crane; \
    rm -f go-containerregistry_Linux_x86_64.tar.gz checksums.txt; \
    crane version

RUN ln -sf /usr/share/zoneinfo/Europe/Copenhagen /etc/localtime

# key-only SSH admin user (caspertdk, see sysusers.d) gets sudo, like the homeserver image
RUN echo "%wheel        ALL=(ALL)       NOPASSWD: ALL" > /etc/sudoers.d/wheel-sudo \
    && chmod 0440 /etc/sudoers.d/wheel-sudo

# Same public keys as the homeserver image (one source of truth), applied by /etc/tmpfiles.d/11-caspertdk-ssh.conf
COPY --chmod=0644 system_files/homeserver/usr/share/homeserver/authorized_keys.pub /usr/share/claude-vm/authorized_keys.pub

COPY system_files/claude-vm/ /
RUN chmod 0755 /usr/bin/claude-vm-seed-github-token /usr/bin/claude-vm-ssh-address /usr/libexec/claude-vm/* \
    && systemctl enable claude-remote-control.service claude-pinggy.service qemu-guest-agent.service bootc-fetch-apply-updates.timer

# var-tmpfiles is skipped: CI bind-mounts the runner's dnf cache at /var/cache/libdnf5 (owned by the
# runner UID, which does not exist in the image), which that lint reports as an unknown user.
RUN bootc container lint --skip var-tmpfiles
