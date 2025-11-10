# syntax=docker/dockerfile:1.19@sha256:b6afd42430b15f2d2a4c5a02b919e98a525b785b1aaff16747d2f623364e39b6
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
      lightdm \
      lightdm-gtk-greeter \
      lightdm-gtk-greeter-settings \
      budgie-desktop \
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

# Ensure LightDM uses the gtk greeter
RUN mkdir -p /etc/lightdm && \
    printf "[Seat:*]\ngreeter-session=lightdm-gtk-greeter\n" > /etc/lightdm/lightdm.conf

# Make graphical the default and ensure LightDM is enabled even if presets run
RUN ln -sf /usr/lib/systemd/system/graphical.target /etc/systemd/system/default.target && \
    && systemctl enable lightdm.service && \
    && mkdir -p /usr/lib/systemd/system-preset && \
    && printf "enable lightdm.service\n" > /usr/lib/systemd/system-preset/99-lightdm.preset

RUN mkdir -p /var/{lib,cache,log}/lightdm \
  && chown lightdm:lightdm /var/{lib,cache,log}/lightdm
  && restorecon -R /var/{lib,cache,log}/lightdm

RUN bootc container lint
