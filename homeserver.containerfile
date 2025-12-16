# syntax=docker/dockerfile:1.20@sha256:26147acbda4f14c5add9946e2fd2ed543fc402884fd75146bd342a7f6271dc1d
FROM quay.io/fedora/fedora-bootc:43 as base

# Split context so cache keys are scoped to the actual inputs per RUN
FROM scratch AS ctx_build
COPY build_files/ /build_files/

FROM scratch AS ctx_system
COPY system_files/ /system_files/

FROM base AS utils
RUN --mount=type=cache,target=/var/cache/dnf \
    dnf -y --setopt=install_weak_deps=false install --allowerasing unzip git-core

RUN --mount=type=bind,from=ctx_build,src=/build_files,dst=/ctx/build_files,ro \
    /utilities.sh


FROM base AS final

# setup sudo to not require password
RUN echo "%wheel        ALL=(ALL)       NOPASSWD: ALL" > /etc/sudoers.d/wheel-sudo

# Write some metadata (append both values to /usr/lib/os-release)
RUN { \
      echo 'VARIANT="HomeServer bootc OS"'; \
      echo 'VARIANT_ID=com.github.caspertdk.homeserver-bootc'; \
    } >> /usr/lib/os-release

# Set timezone
RUN ln -sf /usr/share/zoneinfo/Europe/Copenhagen /etc/localtime

# Registry auth
ARG REGISTRY_URL
ARG REGISTRY_USERNAME

# todo: move to system_files/homeserver/usr/lib/tmpfiles.d/link-podman-credentials.conf ?
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

# PREPARE PACKAGES
COPY --chmod=0644 ./system_files/homeserver/usr/local/share/bootc/packages-added /usr/local/share/bootc/packages-added
COPY --chmod=0644 ./system_files/homeserver/usr/local/share/bootc/packages-removed /usr/local/share/bootc/packages-removed
RUN jq -r .packages[] /usr/share/rpm-ostree/treefile.json > /usr/local/share/bootc/packages-fedora-bootc

RUN --mount=type=cache,target=/var/cache/dnf \
    grep -vE '^#' /usr/local/share/bootc/packages-added \
    | xargs dnf -y install --allowerasing --setopt install_weak_deps=false

RUN --mount=type=cache,target=/var/cache/dnf \
    grep -vE '^#' /usr/local/share/bootc/packages-removed \
    | xargs dnf -y remove

# pip3 dependencies
RUN pip3 install --no-cache-dir --upgrade pip \
    && pip3 install --no-cache-dir glances

RUN --mount=type=bind,from=utils,src=/,dst=/utils,ro \
    mkdir -p /usr/local/share/bash-completion/completions/ \
    && rsync -a /utils/usr/local/bin/* /usr/local/bin \
    && rsync -a /utils/usr/local/share/ /usr/local/share/

# AGE and SOPS
RUN --mount=type=secret,id=agekey,required=true SOPS_AGE_KEY="$(cat /run/secrets/agekey)"; \
    install -D -m 0600 /run/secrets/agekey /usr/lib/sops/age/keys.txt && \
    chown root:root /usr/lib/sops/age/keys.txt && \
    chmod 0640 /usr/lib/sops/age/keys.txt && \
    printf "export SOPS_AGE_KEY=%s\n" "$SOPS_AGE_KEY" | tee /etc/profile.d/61-age-sops-private.sh 1> /dev/null

# Sync /usr and /etc
RUN --mount=type=bind,from=ctx_system,src=/system_files/homeserver,dst=/ctx/system_files/homeserver,ro \
    --mount=type=tmpfs,dst=/tmp \
    rsync -rvpK /ctx/system_files/homeserver/ /

RUN --mount=type=secret,id=registry_token,required=true GITHUB_TOKEN="$(cat /run/secrets/registry_token)"; \
    printf "export GITHUB_TOKEN=%s\n" "$GITHUB_TOKEN" | tee /etc/profile.d/62-registry-auth-private.sh 1> /dev/null

ARG PINGGY_HOST
RUN --mount=type=bind,from=ctx_build,src=/build_files,dst=/ctx/build_files,ro \
    --mount=type=tmpfs,dst=/tmp \
    --mount=type=secret,id=pinggy_token,required=true \
    PINGGY_TOKEN="$(cat /run/secrets/pinggy_token)" \
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


