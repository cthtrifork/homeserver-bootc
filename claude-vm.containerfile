# syntax=docker/dockerfile:1.22@sha256:4a43a54dd1fedceb30ba47e76cfcf2b47304f4161c0caeac2db1c61804ea3c91
#
# Minimal bootc VM image that runs `claude remote-control` as an unprivileged user.
#
# Deliberately contains NO secrets: no registry token, no age/sops key, no SSH or
# deploy keys, no GitHub token. The GitHub token is seeded by hand after first boot
# (see "Claude VM" in README.md), and Claude itself is signed in interactively.
FROM quay.io/fedora/fedora-bootc:44 AS base

FROM base AS final

# renovate: datasource=npm depName=@anthropic-ai/claude-code
ARG CLAUDE_CODE_VERSION=2.1.316

RUN dnf -y install --setopt=install_weak_deps=False \
        git-core gh nodejs npm jq ripgrep tmux qemu-guest-agent \
    && dnf clean all

# Claude Code lives under /usr so it is part of the immutable image and is
# upgraded by bootc, not by an in-place auto-updater.
RUN npm install --global --prefix /usr "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}" \
    && npm cache clean --force \
    && rm -rf /root/.npm /var/roothome/.npm \
    && claude --version

RUN ln -sf /usr/share/zoneinfo/Europe/Copenhagen /etc/localtime

COPY system_files/claude-vm/ /
RUN chmod 0755 /usr/bin/claude-vm-seed-github-token /usr/libexec/claude-vm/run-remote-control \
    && systemctl enable claude-remote-control.service qemu-guest-agent.service

# Guard: fail the build if anything that looks like a private key or token ended up in the image.
RUN set -eu; \
    hits="$(find /etc /root /var/roothome /var/home /usr/local -xdev -type f \
        \( -name 'id_rsa' -o -name 'id_dsa' -o -name 'id_ecdsa' -o -name 'id_ed25519' \
           -o -name '*.pem' -o -name '*.p12' -o -name '*.pfx' -o -name 'ssh_host_*_key' \
           -o -name 'github-token' -o -name '.credentials.json' \) 2>/dev/null || true)"; \
    hits="$hits $(grep -rIlE -e '-----BEGIN [A-Z ]*PRIVATE KEY-----' -e 'gh[pousr]_[A-Za-z0-9]{30,}' -e 'github_pat_[A-Za-z0-9_]{30,}' \
        /etc /root /var/roothome /var/home /usr/local 2>/dev/null || true)"; \
    if [ -n "$(echo "$hits" | tr -d ' \n')" ]; then echo "Secret-like files in image: $hits" >&2; exit 1; fi

RUN bootc container lint
