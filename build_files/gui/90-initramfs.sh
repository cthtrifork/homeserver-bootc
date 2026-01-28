#!/usr/bin/bash
#shellcheck disable=SC2115
set -eou pipefail

# dracut hacks
# https://gitlab.com/fedora/bootc/tracker/-/issues/66#note_2590604787
#cat /etc/dracut.conf.d/no-xattr.conf || true
#export DRACUT_NO_XATTR=1

# Setup Plymouth with theme
#plymouth-set-default-theme spinner
plymouth-set-default-theme bgrt-better-luks

# Update initramfs
# https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/9/html/using_image_mode_for_rhel_to_build_deploy_and_manage_operating_systems/managing-rhel-bootc-images#adding-modules-to-the-bootc-image-initramfs_managing-rhel-bootc-images
set -x
kver=$(cd /usr/lib/modules && echo *)
dracut -vf /usr/lib/modules/$kver/initramfs.img $kver
