# syntax=docker/dockerfile:1.7
FROM scratch AS ctx
COPY / /

FROM quay.io/centos-bootc/centos-bootc:stream9

#setup sudo to not require password
RUN echo "%wheel        ALL=(ALL)       NOPASSWD: ALL" > /etc/sudoers.d/wheel-sudo

# Write some metadata
RUN echo VARIANT="CoreDNS bootc OS" && echo VARIANT_ID=com.github.caspertdk.homeserver-bootc >> /usr/lib/os-release

# Registry auth
ARG REGISTRY_TOKEN="notset"
ARG REGISTRY_URL="notset"
ARG REGISTRY_USERNAME="someuser"
RUN ln -s /run/user/0/containers/auth.json /etc/ostree/auth.json
RUN --mount=type=secret,id=registry_token \
    REGISTRY_TOKEN="$(cat /run/secrets/registry_token)" && \
    printf '%s' "$REGISTRY_TOKEN" | podman login \
      --authfile /etc/ostree/auth.json \
      -u "$REGISTRY_USERNAME" \
      --password-stdin "$REGISTRY_URL"

# Install common utilities
#RUN dnf -y group install 'Development Tools' # this one is huge and includes java!
RUN dnf -y install dnf-plugins-core procps-ng curl file qemu-guest-agent git firewalld rsync unzip
# python3-pip

# Configure repositories
RUN dnf -y install 'dnf-command(config-manager)'

# pip3 dependencies
# RUN pip3 install glances

RUN --mount=type=bind,from=ctx,src=/,dst=/ctx \
    #--mount=type=cache,dst=/var/cache \
    #--mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    --mount=type=secret,id=pinggy_token PINGGY_TOKEN="$(cat /run/secrets/pinggy_token)" \
    /ctx/build_files/build.sh

# Networking
#EXPOSE 8006
#RUN firewall-offline-cmd --add-port 8006/tcp

RUN bootc container lint
