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

# Tooling Claude can use: bash, python (+pip), node (+npm), go, rootless podman.
# bubblewrap + socat are what Claude Code's Bash sandbox needs on Linux.
# Fedora RPMs follow the base image (quay.io/fedora/fedora-bootc, bumped by Renovate).
RUN dnf -y install --setopt=install_weak_deps=False \
        bash python3 python3-pip nodejs npm golang podman shadow-utils fuse-overlayfs \
        bubblewrap socat git-core gh jq ripgrep tmux qemu-guest-agent \
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

RUN ln -sf /usr/share/zoneinfo/Europe/Copenhagen /etc/localtime

# key-only SSH admin user (caspertdk, see sysusers.d) gets sudo, like the homeserver image
RUN echo "%wheel        ALL=(ALL)       NOPASSWD: ALL" > /etc/sudoers.d/wheel-sudo \
    && chmod 0440 /etc/sudoers.d/wheel-sudo

# Same public keys as the homeserver image (one source of truth), applied by /etc/tmpfiles.d/11-caspertdk-ssh.conf
COPY --chmod=0644 system_files/homeserver/usr/share/homeserver/authorized_keys.pub /usr/share/claude-vm/authorized_keys.pub

COPY system_files/claude-vm/ /
RUN chmod 0755 /usr/bin/claude-vm-seed-github-token /usr/libexec/claude-vm/* \
    && systemctl enable claude-remote-control.service qemu-guest-agent.service bootc-fetch-apply-updates.timer

# Guard: fail the build if anything that looks like a private key or token ended up in the image.
RUN set -eu; \
    hits="$(find /etc /root /var/roothome /var/home /usr/local -xdev -type f \
        \( -name 'id_rsa' -o -name 'id_dsa' -o -name 'id_ecdsa' -o -name 'id_ed25519' \
           -o -name '*.p12' -o -name '*.pfx' -o -name 'ssh_host_*_key' \
           -o -name 'github-token' -o -name '.credentials.json' \) 2>/dev/null || true)"; \
    hits="$hits $(grep -rIlE -e '-----BEGIN [A-Z ]*PRIVATE KEY-----' -e 'gh[pousr]_[A-Za-z0-9]{30,}' -e 'github_pat_[A-Za-z0-9_]{30,}' \
        /etc /root /var/roothome /var/home /usr/local 2>/dev/null || true)"; \
    if [ -n "$(echo "$hits" | tr -d ' \n')" ]; then echo "Secret-like files in image: $hits" >&2; exit 1; fi

# var-tmpfiles is skipped: CI bind-mounts the runner's dnf cache at /var/cache/libdnf5 (owned by the
# runner UID, which does not exist in the image), which that lint reports as an unknown user.
RUN bootc container lint --skip var-tmpfiles
