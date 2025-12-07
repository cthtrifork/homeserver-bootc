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
