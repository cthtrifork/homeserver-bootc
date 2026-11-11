# homeserver-bootc

Fedora bootc (`fedora-bootc:44`) images for a home server, built and published by GitHub Actions. Full bootc docs: <https://bootc-dev.github.io/bootc/>

## Images

| Containerfile | Description | Details |
| --- | --- | --- |
| `homeserver.containerfile` | Headless home server | [docs/homeserver](docs/homeserver/README.md) |
| `homeserver-gui.containerfile` | Home server with GUI | [docs/homeserver-gui](docs/homeserver-gui/README.md) |
| `claude-vm.containerfile` | VM that runs Claude Code Remote Control | [docs/claude-vm](docs/claude-vm/README.md) |

The first two bake secrets into the image and must stay private. `claude-vm` is built without any.

## Layout

- `build_files/` – build scripts (base, core, gui, post, ...)
- `system_files/` – files copied into the images
- `tests/` – image verification scripts, one folder per image
- `docs/` – per-image documentation (not in `system_files/`, which is copied into the images)
- `.github/workflows/` – build, lint, cleanup and Renovate pipelines

## Commit and PR titles

Titles follow [Conventional Commits](https://www.conventionalcommits.org/): `type(scope)!: summary`, e.g. `ci(cleanup): run each package as a matrix job`. Allowed types: `feat`, `fix`, `security`, `perf`, `refactor`, `docs`, `test`, `chore`, `revert`, `ci`, `build`, `deps`. The `pr-title` workflow checks the PR title. Squash merges use it as the commit subject, which the changelog of each image release then lists.

## Filesystem notes

- `/usr` is read-only and managed by the image; prefer it for config.
- `/etc` is editable. Locally modified files drift and stop receiving updates. List them with `ostree admin config-diff`, and revert one by copying it from `/usr/etc`.
- `/var` is only populated on first boot.

See also: [Using toolbox to inspect bootc containers](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/9/html/using_image_mode_for_rhel_to_build_deploy_and_manage_operating_systems/managing-rhel-bootc-images#using-toolbx-to-inspect-bootc-containers_managing-rhel-bootc-images)
