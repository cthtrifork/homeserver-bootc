# syntax=docker/dockerfile:1.20@sha256:26147acbda4f14c5add9946e2fd2ed543fc402884fd75146bd342a7f6271dc1d
FROM scratch AS ctx
COPY / /

FROM quay.io/fedora/fedora-bootc:44@sha256:78c9d87fa6940243006b6fa21c89b3b846461a54eb992633f42d68d671faee6c

#setup sudo to not require password
RUN echo "%wheel        ALL=(ALL)       NOPASSWD: ALL" > /etc/sudoers.d/wheel-sudo

# Write some metadata
RUN echo VARIANT="Github Runner bootc OS" && echo VARIANT_ID=com.github.caspertdk.homeserver-bootc >> /usr/lib/os-release

# Registry auth
ARG REGISTRY_URL
ARG REGISTRY_USERNAME

RUN --mount=type=secret,id=creds,required=true cp /run/secrets/creds /usr/lib/container-auth.json && \
    chmod 0600 /usr/lib/container-auth.json && \
    ln -sr /usr/lib/container-auth.json /etc/ostree/auth.json

# Configure repositories
RUN dnf -y install dnf5-plugins dnf-plugins-core procps-ng file qemu-guest-agent \
    # Used by github runner
    lttng-ust openssl-libs krb5-libs zlib libicu \
    # Dev tools
    git rsync unzip jq tree curl \
    # Used by qemu for vmdk+iso creation
    qemu-kvm qemu-img sqlite buildah

# Install docker
RUN --mount=type=bind,from=ctx,src=/,dst=/ctx \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build_files/server-docker-ce.sh

# Create runner user
ARG RUNNER_UID=1001
ARG RUNNER_GID=1001
RUN groupadd -g ${RUNNER_GID} runner \
 && useradd -u ${RUNNER_UID} -g ${RUNNER_GID} runner \
 && usermod -aG docker,wheel runner && \
    mkdir -m 0700 -p /home/runner/ && \
    chown -R runner: /home/runner

ENV RUNNER_VERSION=2.328.0
RUN mkdir -p /usr/lib/actions-runner && \
    curl -fsSL -o /tmp/runner.tgz \
      https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz && \
    tar -xzf /tmp/runner.tgz -C /usr/lib/actions-runner && rm -f /tmp/runner.tgz && \
    chmod -R a+rX /usr/lib/actions-runner

ENV RUNNER_ALLOW_RUNASROOT="1"
ARG REPOSITORY
RUN --mount=type=secret,id=registry_token,required=true GITHUB_TOKEN="$(cat /run/secrets/registry_token)"; \
    mkdir -p /etc/homeserver/metadata && \
    printf "REPOSITORY=%s\nGITHUB_TOKEN=%s\n" "$REPOSITORY" "$GITHUB_TOKEN" > /etc/homeserver/metadata/github-runner && \
    chmod 600 /etc/homeserver/metadata/github-runner

# Install service
RUN --mount=type=bind,from=ctx,src=/,dst=/ctx \
    rsync -rvpK /ctx/system_files/githubrunner/ /

# Cleanup
RUN --mount=type=bind,from=ctx,src=/,dst=/ctx \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build_files/cleanup.sh 

# Setup github-runner.container
RUN --mount=type=bind,from=ctx,src=/,dst=/ctx \
    --mount=type=tmpfs,dst=/tmp \
    mkdir -m 0700 -p /var/lib/github-runner/_work && \
    chown -R ${RUNNER_UID}:${RUNNER_GID} /var/lib/github-runner && \
    mkdir -p /etc/containers/systemd && \
    ln -sr /usr/share/containers/systemd/github-runner.container /etc/containers/systemd/github-runner.container

# Activate services
RUN systemctl enable docker.socket && \
    systemctl enable qemu-guest-agent && \
    systemctl enable podman.socket && \
    systemctl enable actions-runner-config.service && \
    systemctl enable actions-runner.service && \
    systemctl enable podman-auto-update.timer
    
RUN bootc container lint
