/usr/bin/env bash

# dracut hacks
# https://gitlab.com/fedora/bootc/tracker/-/issues/66#note_2590604787
cat /etc/dracut.conf.d/no-xattr.conf || true
export DRACUT_NO_XATTR=1

# Setup Plymouth with theme
plymouth-set-default-theme spinner
systemctl enable plymouth-start.service

# Update initramfs
set -x
kver=$(cd /usr/lib/modules && echo *)
dracut -vf /usr/lib/modules/$kver/initramfs.img $kver
