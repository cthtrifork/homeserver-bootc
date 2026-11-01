# homeserver-bootc

Fedora bootc (`fedora-bootc:44`) images for a home server, built and published by GitHub Actions. Full bootc docs: <https://bootc-dev.github.io/bootc/>

## Images

| Containerfile | Description |
| --- | --- |
| `homeserver.containerfile` | Headless home server |
| `homeserver-gui.containerfile` | Home server with GUI |
| `hello.containerfile` | Minimal Alpine test image |

## Layout

- `build_files/` – build scripts (base, core, gui, post, ...)
- `system_files/` – files copied into the images
- `tests/` – image verification scripts
- `.github/workflows/` – build, lint, cleanup and Renovate pipelines

## Filesystem notes

- `/usr` is read-only and managed by the image; prefer it for config.
- `/etc` is editable. Locally modified files drift and stop receiving updates. List them with `ostree admin config-diff`, and revert one by copying it from `/usr/etc`.
- `/var` is only populated on first boot.

## Remote access

```sh
# ~/.ssh/config
Host portableinfo.pinggy
  HostName portableinfo.a.pinggy.link
  User cthtrifork
  Port 21412
  SetEnv TERM=xterm-256color
```

```sh
ssh -J portableinfo.pinggy cthtrifork@192.168.1.136
```

## Secrets (sops + age)

```sh
sops --encrypt --age "$AGE_PUB" plain > encrypted.sops
SOPS_AGE_KEY_FILE=/var/lib/sops/age/keys.txt sops -d encrypted.sops > plain
```

## Local build test

```sh
echo "" > /tmp/PINGGY_TOKEN
echo "${GITHUB_TOKEN}" > /tmp/REGISTRY_TOKEN
cp "${HOME}/.docker/config.json" /tmp/creds
echo "${SOPS_AGE_KEY}" > /tmp/AGE_KEY
mkdir -p /tmp/runner/.cache/dnf /tmp/runner/.cache/tmp

podman build \
  --network=slirp4netns:enable_ipv6=false \
  -f homeserver-gui.containerfile \
  --build-arg REGISTRY_USERNAME="caspertdk" \
  --build-arg REGISTRY_URL=ghcr.io \
  --build-arg PINGGY_HOST="test.com" \
  --build-arg REPOSITORY="https://github.com/cthtrifork/homeserver-bootc" \
  --secret id=registry_token,src=/tmp/REGISTRY_TOKEN \
  --secret id=pinggy_token,src=/tmp/PINGGY_TOKEN \
  --secret id=creds,src=/tmp/creds \
  --secret id=agekey,src=/tmp/AGE_KEY \
  -v /tmp/runner/.cache/dnf:/var/cache/libdnf5:z \
  -v /tmp/runner/.cache/tmp:/runner/cache:z
```

See also: [Using toolbox to inspect bootc containers](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/9/html/using_image_mode_for_rhel_to_build_deploy_and_manage_operating_systems/managing-rhel-bootc-images#using-toolbx-to-inspect-bootc-containers_managing-rhel-bootc-images)
