#!/usr/bin/env bash
# Usage: image-changelog.sh <image> <changelog-file> <previous-manifest.json> <repo-url>
#
# The rechunker lists every commit since the previous release of the image, whatever it touched, so
# a homeserver release also listed the claude-vm commits merged in between. This rewrites the
# "### Commits" section to the commits since the previous published revision that touched the
# image's own paths (keep in step with the filters in build-bootc-images.yaml).
set -euo pipefail

image="$1" file="$2" manifest="$3" repo_url="$4"

case "$image" in
  homeserver)
    paths=(system_files/homeserver homeserver.containerfile ':(glob)**/homeserver/**' build_files
      ':(exclude)build_files/gui' ':(exclude)build_files/claude-vm' ':(exclude)build_files/claude-vm-utilities.sh'
      cosign.pub policy.json ':(glob)tests/*.sh' .github/actions/set-image-vars .github/actions/prepare-podman
      .github/actions/push-image .github/actions/build-cleanup ':(glob).github/workflows/build-bootc-image*.yaml'
      ':(exclude,glob)**/*.md') ;;
  homeserver-gui)
    paths=(system_files/homeserver-gui system_files/homeserver homeserver-gui.containerfile
      ':(glob)**/homeserver-gui/**' build_files ':(exclude)build_files/claude-vm'
      ':(exclude)build_files/claude-vm-utilities.sh' cosign.pub policy.json ':(exclude,glob)**/*.md') ;;
  claude-vm)
    paths=(system_files/claude-vm claude-vm.containerfile ':(glob)**/claude-vm/**'
      system_files/homeserver/usr/share/homeserver/authorized_keys.pub build_files/claude-vm-utilities.sh
      build_files/download-lib.sh ':(exclude,glob)**/*.md') ;;
  *) echo "unknown image '$image'" >&2; exit 1 ;;
esac

prev="$(jq -r '.Labels["org.opencontainers.image.revision"] // empty' "$manifest" 2>/dev/null || true)"
if [ -z "$prev" ] || ! git cat-file -e "${prev}^{commit}" 2>/dev/null; then
  echo "No usable previous revision; leaving the changelog as the rechunker wrote it"
  exit 0
fi

commits="$(git log --no-merges --format="- **[%h](${repo_url}/commit/%H)** %s" "${prev}..HEAD" -- "${paths[@]}")"
[ -n "$commits" ] || commits="No changes to this image's files"

awk -v c="$commits" '
  /^### Commits/ { print; print c; skip = 1; next }
  /^### Package Changes:/ { skip = 0 }
  !skip { print }
' "$file" > "$file.new"
mv "$file.new" "$file"
