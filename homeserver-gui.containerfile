# syntax=docker/dockerfile:1.21@sha256:27f9262d43452075f3c410287a2c43f5ef1bf7ec2bb06e8c9eeb1b8d453087bc
FROM scratch AS ctx_build
COPY build_files/ /build_files/
COPY system_files/ /system_files/

# this will also inherit all build_files/core/* applied changes
FROM ghcr.io/cthtrifork/homeserver-bootc/homeserver-centos-bootc:latest

RUN dnf copr enable -y scottames/ghostty && \
	dnf copr enable -y sneexy/zen-browser && \
	dnf config-manager addrepo --from-repofile=https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo && \
	dnf install -y "https://repo.linrunner.de/fedora/tlp/repos/releases/tlp-release.fc$(rpm -E %fedora).noarch.rpm" && \
	dnf install -y "https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" && \
	dnf install -y "https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"

# PREPARE PACKAGES
COPY --chmod=0644 ./system_files/homeserver-gui/usr/local/share/kde-bootc/packages-added /usr/local/share/bootc/gui/packages-added
COPY --chmod=0644 ./system_files/homeserver-gui/usr/local/share/kde-bootc/packages-removed /usr/local/share/bootc/gui/packages-removed
RUN jq -r .packages[] /usr/share/rpm-ostree/treefile.json > /usr/local/share/bootc/gui/packages-fedora-bootc

RUN grep -vE '^#' /usr/local/share/bootc/gui/packages-added | xargs dnf -y install --allowerasing --setopt install_weak_deps=false
RUN grep -vE '^#' /usr/local/share/bootc/gui/packages-removed | xargs dnf -y remove

RUN  dnf4 group install multimedia && \
  dnf swap 'ffmpeg-free' 'ffmpeg' --allowerasing && \
  dnf config-manager setopt fedora-cisco-openh264.enabled=1

# Set default applications
RUN xdg-mime default dev.ghostty.Ghostty.desktop x-scheme-handler/terminal

RUN --mount=type=bind,from=ctx_build,src=/,dst=/ctx \
  --mount=type=tmpfs,dst=/tmp \
	--mount=type=cache,target=/runner/cache \
  /ctx/build_files/build.sh "gui"

# Enable GUI by default
RUN systemctl set-default graphical.target

# NetworkManager-wait-online can slow down boot time significantly
RUN systemctl disable NetworkManager-wait-online.service

RUN bootc container lint || true
