# Inspiration: https://gitlab.com/fedora/bootc/examples/-/tree/main/kiosk
FROM ghcr.io/cthtrifork/homeserver-bootc/homeserver-centos-bootc:latest

# Install GUI components (GDM + basic desktop + Firefox)
RUN dnf install -y \
      gdm \
      @budgie-desktop \
      firefox

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


