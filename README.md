# proxmox-fedora-bootc

You can find the full documentation for bootc here: <https://bootc-dev.github.io/bootc/>

## Filesystem notes

The filesystem structure follows ostree specifications:

- The `/usr` directory is read-only, with all changes managed by the container image.
- The `/etc` directory is editable, but any changes applied in the container image will be transferred to the node unless the file was modified locally.
- Changes to `/var` (including /var/home) are made during the first boot. Afterwards, `/var` remains untouched.

As recommended by the bootc project, prioritise using `/usr` and use `/etc` as a fallback if needed.

Please note that a configuration file in `/etc` drifts when it is modified locally. Consequently, bootc will no longer manage this file, and new releases won’t be transferred to your installation. While this might be desired in some cases, it can also lead to issues.
Use `ostree admin config-diff` to list the files in your local /etc that are no longer managed by bootc, because they are modified or added.

> If a particular configuration file needs to be managed by bootc, you can revert it by copying the version created by the container build from `/usr/etc` to `/etc`

## Setup remote access on client

```sh
# ~/.ssh/config
Host portableinfo.pinggy
  HostName portableinfo.a.pinggy.link
  User cthtrifork
  Port 21412
  SetEnv TERM=xterm-256color
```

Connect to a different host through pinggy:

```sh
ssh -J portableinfo.pinggy cthtrifork@192.168.1.136
```

## Links

[Using toolbox](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/9/html/using_image_mode_for_rhel_to_build_deploy_and_manage_operating_systems/managing-rhel-bootc-images#using-toolbx-to-inspect-bootc-containers_managing-rhel-bootc-images)

