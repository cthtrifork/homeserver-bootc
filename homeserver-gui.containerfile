# syntax=docker/dockerfile:1.20@sha256:26147acbda4f14c5add9946e2fd2ed543fc402884fd75146bd342a7f6271dc1d
FROM scratch AS ctx
COPY build_files/ /build_files/
COPY system_files/ /system_files/

FROM ghcr.io/cthtrifork/homeserver-bootc/homeserver-centos-bootc:latest

# SETUP FILESYSTEM
#RUN rmdir /opt && ln -s -T /var/opt /opt
RUN mkdir -p /var/roothome

# Install GUI components (basic desktop + browser + multimedia support)
# Inspiration: https://gitlab.com/fedora/bootc/examples/-/tree/main/kiosk
RUN dnf copr enable -y scottames/ghostty
RUN dnf install -y "https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" && \
    dnf install -y "https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm" && \
    dnf config-manager addrepo --from-repofile=https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo

# PREPARE PACKAGES
COPY --chmod=0644 ./system_files/homeserver-gui/usr/local/share/kde-bootc/packages-added /usr/local/share/bootc/gui/packages-added
COPY --chmod=0644 ./system_files/homeserver-gui/usr/local/share/kde-bootc/packages-removed /usr/local/share/bootc/gui/packages-removed
RUN jq -r .packages[] /usr/share/rpm-ostree/treefile.json > /usr/local/share/bootc/gui/packages-fedora-bootc

RUN grep -vE '^#' /usr/local/share/bootc/gui/packages-added | xargs dnf -y install --allowerasing --setopt install_weak_deps=false
RUN grep -vE '^#' /usr/local/share/bootc/gui/packages-removed | xargs dnf -y remove

# Install VSCode
RUN curl -sLo /tmp/vscode.rpm "https://code.visualstudio.com/sha/download?build=stable&os=linux-rpm-x64" && \
    dnf --nogpgcheck -y install /tmp/vscode.rpm && \
    rm -f /tmp/vscode.rpm

# Install fonts
# Jetbrains nerd font
RUN mkdir -p /usr/share/fonts/JetBrainsMono && wget -O /usr/share/fonts/JetBrainsMono/JetBrainsMono.zip https://download.jetbrains.com/fonts/JetBrainsMono-2.304.zip \
	&& cd /usr/share/fonts/JetBrainsMono \
	&& unzip JetBrainsMono.zip \
	&& rm JetBrainsMono.zip \
	&& fc-cache -f -vv

# Clone and install Segoe UI font
ENV DEST_DIR="/usr/share/fonts/Microsoft/TrueType/SegoeUI/" 
RUN git clone https://github.com/mrbvrz/segoe-ui-linux /tmp/segoe-ui-linux \
    && mkdir -p "$DEST_DIR" \
    && cp -r /tmp/segoe-ui-linux/font/*.ttf $DEST_DIR/ \
    && rm -rf /tmp/segoe-ui-linux \
    && fc-cache -f "$DEST_DIR"

# Cleanup
RUN --mount=type=bind,from=ctx,src=/,dst=/ctx \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build_files/cleanup.sh

# Do not run pinggy on a GUI client
RUN systemctl disable pinggy.service && \
	systemctl enable NetworkManager

# Enable GUI by default
RUN systemctl set-default graphical.target

RUN bootc container lint


