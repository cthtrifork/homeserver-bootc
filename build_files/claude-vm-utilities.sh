#!/usr/bin/env bash
#
# Installs the static release binaries the claude-vm image needs (crane, hadolint, actionlint).
# Same pattern as core/09-utilities.sh: downloads are kept under /runner/cache (the CI runner cache,
# bind-mounted by the build workflow) so unchanged versions are not downloaded again.
# Unlike 09-utilities.sh every download is checksum-verified against the release's own checksum file,
# which is always fetched fresh, so a poisoned or corrupt cache entry fails the build.
#
# Versions are bumped by Renovate (the `# renovate:` comments, see .github/renovate.json5).
set -euo pipefail

BIN_DIR="/usr/bin"
CACHE_DIR="/runner/cache"
mkdir -p "$CACHE_DIR"

log() { echo "=== $* ==="; }

tmp_name() {
    # Usage: tmp_name <name> <version> <ext>
    local safe_version="${2//\//-}"
    echo "${CACHE_DIR}/${1}-${safe_version// /_}.${3}"
}

fetch() {
    # Usage: fetch <dest> <url>
    curl -fsSL --retry 5 --retry-delay 5 --retry-all-errors -o "$1.part" "$2" && mv "$1.part" "$1"
}

download_if_missing() {
    # Usage: download_if_missing <dest> <url>
    if [[ -f "$1" ]]; then
        echo "[DEBUG] Using cached $1" >&2
        return 0
    fi
    fetch "$1" "$2"
}

verify() {
    # Usage: verify <file> <asset-name-in-checksum-file> <checksum-file>
    # Checksum lines look like "<sha256>  <name>" or "<sha256> *<name>".
    local want
    want="$(awk -v n="$2" '{f=$2; sub(/^\*/, "", f); if (f == n) {print $1; exit}}' "$3")"
    [[ -n "$want" ]] || { echo "No checksum for $2 in $3" >&2; return 1; }
    echo "${want}  $1" | sha256sum -c -
}

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

log "Installing crane"
CRANE_VERSION=v0.22.1 # renovate: datasource=github-releases depName=google/go-containerregistry
CRANE_TGZ="$(tmp_name crane "$CRANE_VERSION" tar.gz)"
base="https://github.com/google/go-containerregistry/releases/download/${CRANE_VERSION}"
download_if_missing "$CRANE_TGZ" "${base}/go-containerregistry_Linux_x86_64.tar.gz"
fetch "$work/crane.sum" "${base}/checksums.txt"
verify "$CRANE_TGZ" go-containerregistry_Linux_x86_64.tar.gz "$work/crane.sum"
tar -xzf "$CRANE_TGZ" -C "$BIN_DIR" crane
crane version

log "Installing hadolint"
HADOLINT_VERSION=v2.15.1 # renovate: datasource=github-releases depName=hadolint/hadolint
HADOLINT_BIN="$(tmp_name hadolint "$HADOLINT_VERSION" bin)"
base="https://github.com/hadolint/hadolint/releases/download/${HADOLINT_VERSION}"
download_if_missing "$HADOLINT_BIN" "${base}/hadolint-linux-x86_64"
fetch "$work/hadolint.sum" "${base}/checksums.sha256"
verify "$HADOLINT_BIN" hadolint-linux-x86_64 "$work/hadolint.sum"
install -o root -g root -m 0755 "$HADOLINT_BIN" "$BIN_DIR/hadolint"
hadolint --version

log "Installing actionlint"
ACTIONLINT_VERSION=v1.7.12 # renovate: datasource=github-releases depName=rhysd/actionlint
ver="${ACTIONLINT_VERSION#v}"
ACTIONLINT_TGZ="$(tmp_name actionlint "$ACTIONLINT_VERSION" tar.gz)"
base="https://github.com/rhysd/actionlint/releases/download/${ACTIONLINT_VERSION}"
download_if_missing "$ACTIONLINT_TGZ" "${base}/actionlint_${ver}_linux_amd64.tar.gz"
fetch "$work/actionlint.sum" "${base}/actionlint_${ver}_checksums.txt"
verify "$ACTIONLINT_TGZ" "actionlint_${ver}_linux_amd64.tar.gz" "$work/actionlint.sum"
tar -xzf "$ACTIONLINT_TGZ" -C "$BIN_DIR" actionlint
actionlint -version
