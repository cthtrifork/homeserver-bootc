# homeserver-gui

`homeserver-gui.containerfile` builds `homeserver-gui-bootc`: the [home server](../homeserver/README.md) plus a KDE
Plasma desktop. Back to the [main README](../../README.md).

> **Private image**, for the same reason as the home server: it takes the same build secrets (age key, registry and
> pinggy tokens). See [homeserver](../homeserver/README.md#what-is-in-it).

## Overview

```mermaid
flowchart TD
    HS["homeserver image<br/>(files, tools, secrets, services)"] --> IMG
    BASE["fedora-bootc:44"] --> IMG
    subgraph IMG["homeserver-gui image (PRIVATE: same baked secrets)"]
        KDE["KDE Plasma + SDDM + KDE apps<br/>PipeWire, NetworkManager Wi-Fi, TLP"]
        APPS["Apps<br/>zen-browser, ghostty, VS Code, Zed,<br/>virt-manager, trivy-scanner,<br/>harper-pad, yaml-schema-router, multimedia codecs"]
        BOOTX["Boot<br/>Plymouth bgrt-better-luks, Clevis LUKS,<br/>dracut initramfs, graphical.target"]
        DEF["Defaults<br/>hostname kde-homeserver,<br/>Danish keymap, SDDM hides runner"]
        NOPING["pinggy.service DISABLED"]
    end
    TIMER["bootc-fetch-apply-updates.timer<br/>daily 00:30"] --> UPG["bootc upgrade<br/>(no reboot)"]
    REG[("ghcr.io")] --> UPG
    IMG --> UPG
    IMG --> FB["First user setup<br/>VS Code extensions, dotfiles"]
```

## How it differs

- **Files:** `system_files/homeserver/` and `system_files/homeserver-gui/` are both copied in, the GUI tree second.
- **Packages:** `system_files/homeserver-gui/usr/local/share/kde-bootc/packages-added` and `packages-removed`: Plasma,
  SDDM, KDE apps, fonts, zen-browser, ghostty, the libvirt/virt-manager stack, NetworkManager with Wi-Fi, PipeWire,
  TLP and Clevis for LUKS. Multimedia codecs come from the `multimedia` group with ffmpeg swapped in.
- **Extra software** (`build_files/gui/`): VS Code from Microsoft's repo, Zed, yaml-schema-router and the
  trivy-scanner (`cthtrifork/trivy-dashboard-wail3`) and harper-pad (`cthtrifork/harper-pad`) RPMs. Versions use `# renovate:` comments.
- **Defaults:** Danish console keymap, hostname `kde-homeserver`, VS Code extensions installed by the first user setup, SDDM
  hides the `runner` user, and the graphical target is the default.
- **Boot:** Plymouth theme `bgrt-better-luks`, kernel args `quiet rhgb`, initramfs rebuilt with dracut.
- **No pinggy tunnel:** `build_files/gui/21-systemd.sh` disables `pinggy.service`.
- **Updates:** `bootc-fetch-apply-updates.timer` runs daily at 00:30 and `bootc upgrade` does not reboot, because
  this is a client machine. Drop-ins are in `usr/lib/systemd/system/bootc-fetch-apply-updates.*.d/`.

## CI

Builds and E2E run on the `arc-ubuntu` runner because of disk size, and rechunking uses 36 layers instead of 32.
Local builds work as in [homeserver](../homeserver/README.md#local-build-test) with `-f homeserver-gui.containerfile`.

## Tests

`tests/homeserver-gui/system-test.sh` and `user-test.sh`, run in QEMU when a pull request has the `e2e` label, plus
the shared `tests/diagnostics.sh`.
