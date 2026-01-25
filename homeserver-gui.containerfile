# syntax=docker/dockerfile:1.21@sha256:27f9262d43452075f3c410287a2c43f5ef1bf7ec2bb06e8c9eeb1b8d453087bc
FROM scratch AS ctx
COPY build_files/ /build_files/
COPY system_files/ /system_files/

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

# Set default applications
RUN xdg-mime default dev.ghostty.Ghostty.desktop x-scheme-handler/terminal

# Install VSCode
RUN --mount=type=bind,from=ctx,src=/,dst=/ctx \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build_files/gui-vscode.sh

# Sync /usr and /etc
RUN --mount=type=bind,from=ctx,src=/,dst=/ctx \
    --mount=type=tmpfs,dst=/tmp \
    rsync -rvpK /ctx/system_files/homeserver/ / \
    && rsync -rvpK /ctx/system_files/homeserver-gui/ /

RUN echo "KEYMAP=dk" | tee -a /etc/vconsole.conf

#RUN kver=$(cd /usr/lib/modules && echo * | awk '{print $1}') \
#	dracut -vf /usr/lib/modules/$kver/initramfs.img $kver

RUN cat /etc/dracut.conf.d/no-xattr.conf || true
ENV DRACUT_NO_XATTR=1

RUN plymouth-set-default-theme spinner && \
  systemctl enable plymouth-start.service

RUN dnf install -y clevis clevis-dracut clevis-luks clevis-systemd
RUN set -x; kver=$(cd /usr/lib/modules && echo *); dracut -vf /usr/lib/modules/$kver/initramfs.img $kver

# Cleanup
RUN --mount=type=bind,from=ctx,src=/,dst=/ctx \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build_files/cleanup.sh

# Do not run pinggy on a GUI client
RUN systemctl disable pinggy.service && \
	systemctl enable NetworkManager && \
	systemctl enable tlp.service && \
	systemctl enable tlp-pd.service && \
	systemctl mask systemd-rfkill.service systemd-rfkill.socket && \
  systemctl mask systemd-networkd-wait-online.service

# Enable GUI by default
RUN systemctl set-default graphical.target

RUN bootc container lint || true
