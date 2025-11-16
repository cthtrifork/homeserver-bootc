# syntax=docker/dockerfile:1.20@sha256:26147acbda4f14c5add9946e2fd2ed543fc402884fd75146bd342a7f6271dc1d
FROM scratch AS ctx
COPY build_files/ /build_files/
COPY system_files/ /system_files/

FROM ghcr.io/cthtrifork/homeserver-bootc/homeserver-centos-bootc:latest

# Install GUI components (GDM + basic desktop + browser + multimedia support)
# Inspiration: https://gitlab.com/fedora/bootc/examples/-/tree/main/kiosk
RUN dnf copr enable -y scottames/ghostty
RUN dnf install -y "https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" && \
    dnf install -y "https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm" && \
    dnf config-manager addrepo --from-repofile=https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo

RUN dnf -y --setopt=install_weak_deps=false install \
      gdm \
      gnome-session \
      budgie-desktop \
      budgie-desktop-view \
      budgie-backgrounds \
      budgie-session \
      gnome-session-xsession \
      gnome-shell \
      budgie-control-center \
      budgie-screensaver \
      xorg-x11-server-Xorg \
      xorg-x11-xauth \
      xorg-x11-xinit \
      mesa-dri-drivers \
      mesa-libGL \
      dbus-daemon \
      polkit \
      NetworkManager \
      ghostty \
      ffmpeg

# todo: budgie-extras ?
RUN dnf -y remove gnome-shell-extension-* gnome-tour

# Install VSCode
RUN curl -sLo /tmp/vscode.rpm "https://code.visualstudio.com/sha/download?build=stable&os=linux-rpm-x64" && \
    dnf --nogpgcheck -y install /tmp/vscode.rpm && \
    rm -f /tmp/vscode.rpm

# Copy custom configuration files
RUN rm -rf /var/lib/gdm/.config/pulse/default.pa && rm -rf /var/lib/xkb/README.compiled
COPY system_files/homeserver-gui/custom.conf /etc/gdm/

# Cleanup
RUN --mount=type=bind,from=ctx,src=/,dst=/ctx \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build_files/cleanup.sh

# Do not run pinggy on a GUI client
RUN systemctl disable pinggy.service && \
	systemctl enable NetworkManager && \
	gnome-extensions enable dash-to-panel@jderose9.github.com

# Enable GUI by default
RUN systemctl set-default graphical.target && \
    systemctl enable gdm.service

RUN bootc container lint