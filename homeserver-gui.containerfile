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


# wofi	App launcher (like rofi, but Wayland-native)
# mako	Notification daemon
# brightnessctl	Adjust screen brightness
# pavucontrol	Manage audio (PulseAudio or PipeWire GUI)
# waybar status bar
# grim+slurp screenshot manager

# https://gist.github.com/quangdinh/41cb26e0abb34c5242e55004bd411065
# https://www.reddit.com/r/swaywm/comments/11rc1a9/just_a_rice_post_with_wofi_and_waybar_configs_i/

RUN dnf install -y \
      brave-browser \
      ghostty \
      ffmpeg \
      wofi \
      mako \
      brightnessctl \
      pavucontrol \
      sway \
      waybar \
      wlogout \
      grim \
      slurp \
      wl-clipboard

RUN dnf group install -y @"Sway Desktop"
RUN dnf swap @workstation-product-environment @"Sway Desktop"
RUN dnf swap fedora-release-identity-workstation fedora-release-identity-sway
RUN dnf remove gnome-*

# Install VSCode
RUN curl -sLo /tmp/vscode.rpm "https://code.visualstudio.com/sha/download?build=stable&os=linux-rpm-x64" && \
    dnf --nogpgcheck -y install /tmp/vscode.rpm && \
    rm -f /tmp/vscode.rpm

# RUN rm -rf /var/lib/gdm/.config/pulse/default.pa && rm -rf /var/lib/xkb/README.compiled

# Install service
RUN --mount=type=bind,from=ctx,src=/,dst=/ctx \
    rsync -rvpK /ctx/system_files/homeserver-gui/ /

# Cleanup
RUN --mount=type=bind,from=ctx,src=/,dst=/ctx \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build_files/cleanup.sh

# Do not run pinggy on a GUI client
RUN systemctl disable pinggy.service

# Enable GUI by default
RUN systemctl set-default graphical.target
# systemctl enable gdm.service

RUN bootc container lint



