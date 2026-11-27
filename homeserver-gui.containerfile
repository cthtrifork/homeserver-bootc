# syntax=docker/dockerfile:1.29@sha256:572cebbc2b15e6f84c077742952674889cb63cd5e9b80abdffcbe587b6f19183
ARG CORE_IMAGE=core
FROM quay.io/fedora/fedora-bootc:45 AS base

FROM scratch AS ctx_build
COPY build_files/ /build_files/
COPY system_files/ /system_files/

FROM base AS core
# Repo hosts, pinned instead of the metalinks; keep in step with the arc-runner egress policy in talos-gitops.
ARG FEDORA_MIRROR=https://dl.fedoraproject.org/pub/fedora
ARG RPMFUSION_MIRROR=https://download1.rpmfusion.org
# Removed in build_files/post/90-cleanup.sh.
RUN mkdir -p /etc/dnf/repos.override.d && printf '%s\n' \
      '[fedora]' 'metalink=' "baseurl=${FEDORA_MIRROR}/linux/releases/\$releasever/Everything/\$basearch/os/" \
      '[updates]' 'metalink=' "baseurl=${FEDORA_MIRROR}/linux/updates/\$releasever/Everything/\$basearch/" \
      '[updates-archive]' 'enabled=0' \
      '[rpmfusion-free]' 'metalink=' "baseurl=${RPMFUSION_MIRROR}/free/fedora/releases/\$releasever/Everything/\$basearch/os/" \
      '[rpmfusion-free-updates]' 'metalink=' "baseurl=${RPMFUSION_MIRROR}/free/fedora/updates/\$releasever/\$basearch/" \
      '[rpmfusion-nonfree]' 'metalink=' "baseurl=${RPMFUSION_MIRROR}/nonfree/fedora/releases/\$releasever/Everything/\$basearch/os/" \
      '[rpmfusion-nonfree-updates]' 'metalink=' "baseurl=${RPMFUSION_MIRROR}/nonfree/fedora/updates/\$releasever/\$basearch/" \
    > /etc/dnf/repos.override.d/50-mirror.repo
# tsflags=nodocs: do not install files marked as documentation (man pages and /usr/share/doc included). /usr/share/doc is
# deleted at the end of the build anyway (build_files/post/90-cleanup.sh), so this only saves writing it.
RUN echo -e "keepcache=True\nmetadata_expire=6h\nip_resolve=4\nfastestmirror=True\ntsflags=nodocs" >> /etc/dnf/dnf.conf
# Changes every week (the workflow passes it): the layers after it expire then, so the layer cache never freezes package updates
ARG CACHE_BUST=0
RUN echo "layer cache key: ${CACHE_BUST}"
RUN dnf -y install dnf5-plugins && dnf5 config-manager setopt keepcache=1

RUN [ -e /etc/subuid ] || touch /etc/subuid; \
    [ -e /etc/subgid ] || touch /etc/subgid

# setup sudo to not require password
RUN echo "%wheel        ALL=(ALL)       NOPASSWD: ALL" > /etc/sudoers.d/wheel-sudo

# Write some metadata (append both values to /usr/lib/os-release)
RUN { \
      echo 'VARIANT="HomeServer bootc OS"'; \
      echo 'VARIANT_ID=com.github.caspertdk.homeserver-bootc'; \
    } >> /usr/lib/os-release

# Set timezone
RUN ln -sf /usr/share/zoneinfo/Europe/Copenhagen /etc/localtime

# PREPARE PACKAGES
# COPY instead of a bind mount: the layer cache hashes COPY, but never reuses a RUN with a --mount from another stage
COPY --from=ctx_build /system_files/homeserver/ /tmp/system_files/homeserver/
COPY --from=ctx_build /system_files/homeserver-gui/ /tmp/system_files/homeserver-gui/
RUN dnf -y install --setopt install_weak_deps=false rsync && \
  rsync -rvpKl /tmp/system_files/homeserver/ /tmp/system_files/homeserver-gui/ \
  / && \
  rm -rf /tmp/system_files

RUN cat /usr/local/share/bootc/packages-added /usr/local/share/kde-bootc/packages-added | grep -vE '^#' | xargs -r dnf -y install --allowerasing --setopt install_weak_deps=false && \
    cat /usr/local/share/bootc/packages-removed /usr/local/share/kde-bootc/packages-removed | grep -vE '^#' | xargs -r dnf -y remove

# multimedia
RUN dnf group install -y multimedia && \
  dnf swap -y 'ffmpeg-free' 'ffmpeg' --allowerasing && \
  dnf config-manager setopt fedora-cisco-openh264.enabled=1

# Set default applications
#RUN xdg-mime default dev.ghostty.Ghostty.desktop x-scheme-handler/terminal

# Everything above is secret-free and goes in the layer cache (core). Everything below uses secrets and is built on
# top of it without the cache; CI passes CORE_IMAGE (the built core image), a plain build uses the stage.
FROM ${CORE_IMAGE} AS final
# Registry auth
ARG REGISTRY_URL
ARG REGISTRY_USERNAME

RUN --mount=type=bind,from=ctx_build,src=/,dst=/ctx --mount=type=secret,id=creds,required=true \
    /ctx/build_files/container-auth.sh

# AGE and SOPS
RUN --mount=type=bind,from=ctx_build,src=/,dst=/ctx --mount=type=secret,id=agekey,required=true /ctx/build_files/sops.sh

# Registry/GitHub token: root-only file, read at runtime (copied 0600 to the user via tmpfiles.d)
RUN --mount=type=secret,id=registry_token,required=true \
    install -D -m 0600 -o root -g root /run/secrets/registry_token /usr/lib/homeserver/github-token

ARG PINGGY_HOST
RUN --mount=type=bind,from=ctx_build,src=/,dst=/ctx \
    --mount=type=tmpfs,dst=/tmp \
    --mount=type=secret,id=pinggy_token,required=true \
    --mount=type=secret,id=github_api_token \
    /ctx/build_files/build.sh "/ctx/build_files/base" \
    && PINGGY_TOKEN="$(cat /run/secrets/pinggy_token)" \
    PINGGY_HOST="${PINGGY_HOST}" /ctx/build_files/build.sh "/ctx/build_files/core" \
    && /ctx/build_files/build.sh "/ctx/build_files/gui" \
    && /ctx/build_files/build.sh "/ctx/build_files/post"

# COSIGN
ADD --chmod=0644 cosign.pub /etc/pki/cosign/cosign.pub
ADD --chmod=0644 policy.json /etc/containers/policy.json

# var-tmpfiles is skipped: CI bind-mounts the runner's dnf cache at /var/cache/libdnf5 (owned by the
# runner UID, which does not exist in the image), which that lint reports as an unknown user.
RUN bootc container lint --skip var-tmpfiles
