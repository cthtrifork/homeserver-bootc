# Inspiration: https://gitlab.com/fedora/bootc/examples/-/tree/main/kiosk
FROM ghcr.io/cthtrifork/homeserver-bootc/homeserver-centos-bootc:latest

RUN dnf install -y gdm firefox plymouth-system-theme
RUN rm -rf /var/lib/gdm/.config/pulse/default.pa && rm -rf /var/lib/xkb/README.compiled
COPY system_files/homeserver-gui/custom.conf /etc/gdm/

RUN systemctl set-default graphical.target

# Cleanup
RUN --mount=type=bind,from=ctx,src=/,dst=/ctx \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build_files/cleanup.sh 

RUN bootc container lint
