# syntax=docker/dockerfile:1.19@sha256:b6afd42430b15f2d2a4c5a02b919e98a525b785b1aaff16747d2f623364e39b6
FROM scratch AS ctx
COPY / /

FROM ghcr.io/cthtrifork/homeserver-bootc/homeserver-centos-bootc:latest

# Install GUI components (GDM + basic desktop + browser + multimedia support)
# Inspiration: https://gitlab.com/fedora/bootc/examples/-/tree/main/kiosk
RUN dnf copr enable -y scottames/ghostty
RUN dnf install -y "https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" && \
    dnf install -y "https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm" && \
    dnf config-manager addrepo --from-repofile=https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo
RUN dnf install -y --setopt install_weak_deps=false \
      lightdm \
      lightdm-gtk \
      @budgie-desktop \
      brave-browser \
      ghostty \
      ffmpeg

# Install VSCode
RUN curl -sLo /tmp/vscode.rpm "https://code.visualstudio.com/sha/download?build=stable&os=linux-rpm-x64" && \
    dnf --nogpgcheck -y install /tmp/vscode.rpm && \
    rm -f /tmp/vscode.rpm

# Cleanup
RUN --mount=type=bind,from=ctx,src=/,dst=/ctx \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build_files/cleanup.sh

# Do not run pinggy on a GUI client
RUN systemctl disable pinggy.service

# Enable GUI by default
RUN systemctl set-default graphical.target && \
    systemctl enable lightdm

RUN bootc container lint


