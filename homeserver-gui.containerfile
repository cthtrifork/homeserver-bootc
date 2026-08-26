# syntax=docker/dockerfile:1.22@sha256:4a43a54dd1fedceb30ba47e76cfcf2b47304f4161c0caeac2db1c61804ea3c91
FROM quay.io/fedora/fedora-bootc:44 AS base

FROM scratch AS ctx_build
COPY build_files/ /build_files/
COPY system_files/ /system_files/

FROM base AS final
RUN echo -e "keepcache=True\nmetadata_expire=6h\nip_resolve=4\nfastestmirror=True" >> /etc/dnf/dnf.conf
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

# Registry auth
ARG REGISTRY_URL
ARG REGISTRY_USERNAME

RUN --mount=type=bind,from=ctx_build,src=/,dst=/ctx --mount=type=secret,id=creds,required=true \
    /ctx/build_files/container-auth.sh

# PREPARE PACKAGES
# GUI
RUN dnf copr enable -y sneexy/zen-browser && \
dnf copr enable -y scottames/ghostty && \
dnf install -y "https://repo.linrunner.de/fedora/tlp/repos/releases/tlp-release.fc$(rpm -E %fedora).noarch.rpm" && \
dnf install -y "https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" && \
dnf install -y "https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"

COPY --chmod=0644 ./system_files/homeserver/usr/local/share/bootc/* /usr/local/share/bootc/
COPY --chmod=0644 ./system_files/homeserver-gui/usr/local/share/kde-bootc/* /usr/local/share/kde-bootc/
RUN jq -r .packages[] /usr/share/rpm-ostree/treefile.json > /usr/local/share/bootc/packages-fedora-bootc

RUN cat /usr/local/share/bootc/packages-added /usr/local/share/kde-bootc/packages-added | grep -vE '^#' | xargs -r dnf -y install --allowerasing --setopt install_weak_deps=false && \
    cat /usr/local/share/bootc/packages-removed /usr/local/share/kde-bootc/packages-removed | grep -vE '^#' | xargs -r dnf -y remove

# multimedia
RUN dnf group install -y multimedia && \
  dnf swap -y 'ffmpeg-free' 'ffmpeg' --allowerasing && \
  dnf config-manager setopt fedora-cisco-openh264.enabled=1

# Set default applications
#RUN xdg-mime default dev.ghostty.Ghostty.desktop x-scheme-handler/terminal

# AGE and SOPS
RUN --mount=type=bind,from=ctx_build,src=/,dst=/ctx --mount=type=secret,id=agekey,required=true /ctx/build_files/sops.sh

RUN --mount=type=secret,id=registry_token,required=true GITHUB_TOKEN="$(cat /run/secrets/registry_token)"; \
    printf "export GITHUB_TOKEN=%s\n" "$GITHUB_TOKEN" | tee /etc/profile.d/62-registry-auth-private.sh 1> /dev/null

ARG PINGGY_HOST
RUN --mount=type=bind,from=ctx_build,src=/,dst=/ctx \
    --mount=type=tmpfs,dst=/tmp \
    --mount=type=secret,id=pinggy_token,required=true \
    /ctx/build_files/build.sh "/ctx/build_files/base" \
    && PINGGY_TOKEN="$(cat /run/secrets/pinggy_token)" \
    PINGGY_HOST="${PINGGY_HOST}" /ctx/build_files/build.sh "/ctx/build_files/core" \
    && /ctx/build_files/build.sh "/ctx/build_files/gui" \
    && /ctx/build_files/build.sh "/ctx/build_files/post"

# COSIGN
ADD --chmod=0644 cosign.pub /etc/pki/cosign/cosign.pub
ADD --chmod=0644 policy.json /etc/containers/policy.json

# Enable GUI by default
RUN systemctl set-default graphical.target

# NetworkManager-wait-online can slow down boot time significantly
RUN systemctl disable NetworkManager-wait-online.service

# RUN bootc container lint
