# Generate repos configuration

```sh
podman run --rm -it \
  -v "${PWD}/system_files/homeserver-gui/etc/yum.repos.d/:/out/repos:Z" \
  -v "${PWD}/system_files/homeserver-gui/etc/pki/rpm-gpg/:/out/rpm-gpg:Z" \
  quay.io/fedora/fedora:44 \
  bash

# inside container
dnf install -y dnf5-plugins

dnf copr enable -y sneexy/zen-browser
dnf copr enable -y scottames/ghostty

dnf install -y \
  https://repo.linrunner.de/fedora/tlp/repos/releases/tlp-release.fc44.noarch.rpm

dnf install -y \
  https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-44.noarch.rpm \
  https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-44.noarch.rpm

# Copy files
cp -a /etc/yum.repos.d/*.repo /out/repos
cp -a /etc/pki/rpm-gpg/* /out/rpm-gpg/
```
