# syntax=docker/dockerfile:1.19@sha256:b6afd42430b15f2d2a4c5a02b919e98a525b785b1aaff16747d2f623364e39b6
FROM scratch AS ctx
COPY / /

FROM ghcr.io/cthtrifork/homeserver-bootc/homeserver-centos-bootc:latest

# Install GUI components (GDM + basic desktop + Firefox)
# Inspiration: https://gitlab.com/fedora/bootc/examples/-/tree/main/kiosk
RUN dnf copr enable -y scottames/ghostty
RUN dnf install -y \
      gdm \
      budgie-session \
      plymouth-system-theme \
      firefox \
      ghostty \
      curl

RUN curl -sLo /tmp/vscode.rpm "https://code.visualstudio.com/sha/download?build=stable&os=linux-rpm-x64" && \
    dnf install -y /tmp/vscode.rpm && \
    rm -f /tmp/vscode.rpm

RUN rm -rf /var/lib/gdm/.config/pulse/default.pa && rm -rf /var/lib/xkb/README.compiled
COPY system_files/homeserver-gui/custom.conf /etc/gdm/

# Cleanup
RUN --mount=type=bind,from=ctx,src=/,dst=/ctx \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build_files/cleanup.sh

# Do not run pinggy on a GUI client
RUN systemctl disable pinggy.service

# Enable GUI by default
RUN systemctl set-default graphical.target && \
    systemctl enable gdm.service

RUN bootc container lint
