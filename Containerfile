# syntax=docker/dockerfile:1.19@sha256:b6afd42430b15f2d2a4c5a02b919e98a525b785b1aaff16747d2f623364e39b6
FROM scratch AS ctx
COPY / /

FROM quay.io/fedora/fedora-bootc:42

#setup sudo to not require password
RUN echo "%wheel        ALL=(ALL)       NOPASSWD: ALL" > /etc/sudoers.d/wheel-sudo

# Write some metadata
RUN echo VARIANT="HomeServer bootc OS" && echo VARIANT_ID=com.github.caspertdk.homeserver-bootc >> /usr/lib/os-release

# Set timezone
RUN ln -sf /usr/share/zoneinfo/Europe/Copenhagen /etc/localtime

# Registry auth
ARG REGISTRY_URL
ARG REGISTRY_USERNAME

RUN --mount=type=secret,id=creds,required=true \
    cp /run/secrets/creds /usr/lib/container-auth.json && \
    chmod 0600 /usr/lib/container-auth.json && \
    \
    # For rpm-ostree / bootc / ostree-container pulls
    ln -sf /usr/lib/container-auth.json /etc/ostree/auth.json && \
    \
    # For podman/skopeo/buildah (root context)
    mkdir -p /etc/containers && \
    ln -sf /usr/lib/container-auth.json /etc/containers/auth.json && \
    \
    # For docker CLI (real Docker or the podman-docker shim): per-daemon fallback
    mkdir -p /etc/docker && \
    ln -sf /usr/lib/container-auth.json /etc/docker/config.json

# Install common utilities
#RUN dnf -y group install 'Development Tools' # this one is huge and includes java!
RUN dnf -y install \
      dnf5-plugins \
      ca-certificates \
      dnf-plugins-core \
      procps-ng \
      curl \
      file \
      qemu-guest-agent \
      firewalld \
      rsync \
      unzip \
      python3 \
      python3-pip \
      tree \
      git \
      make

# pip3 dependencies
RUN pip3 install glances

RUN --mount=type=secret,id=registry_token,required=true GITHUB_TOKEN="$(cat /run/secrets/registry_token)"; \
    printf "export GITHUB_TOKEN=%s\n" "$GITHUB_TOKEN" | tee /etc/profile.d/89-github-auth.sh
ARG PINGGY_HOST
RUN --mount=type=bind,from=ctx,src=/,dst=/ctx \
    #--mount=type=cache,dst=/var/cache \
    #--mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    --mount=type=secret,id=pinggy_token,required=true PINGGY_TOKEN="$(cat /run/secrets/pinggy_token)" \
    PINGGY_HOST="${PINGGY_HOST}" \
    /ctx/build_files/build.sh

# COSIGN
ADD cosign.pub /etc/pki/cosign/cosign.pub
ADD policy.json /etc/containers/policy.json
RUN chmod 0644 /etc/pki/cosign/cosign.pub /etc/containers/policy.json

# Networking
#EXPOSE 8006
#RUN firewall-offline-cmd --add-port 8006/tcp

RUN bootc container lint
