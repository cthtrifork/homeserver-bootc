# syntax=docker/dockerfile:1.21@sha256:27f9262d43452075f3c410287a2c43f5ef1bf7ec2bb06e8c9eeb1b8d453087bc
FROM scratch AS ctx
COPY / /

FROM quay.io/fedora/fedora-bootc:42

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
RUN dnf -y install dnf-plugins-core procps-ng file qemu-guest-agent \
    # Dev tools
    rsync tree

# Create directories for caddy services
RUN mkdir -p /etc/caddy/demo-backend && \
    mkdir -p /etc/caddy/reverse-proxy

# Install service
RUN --mount=type=bind,from=ctx,src=/,dst=/ctx \
    rsync -rvpK /ctx/system_files/jumphost/ /

# Cleanup
RUN --mount=type=bind,from=ctx,src=/,dst=/ctx \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build_files/cleanup.sh 

# Activate services
RUN systemctl enable qemu-guest-agent && \
    systemctl enable podman.socket && \
    systemctl enable caddy-config.service && \
    systemctl enable podman-auto-update.timer
    
RUN bootc container lint
