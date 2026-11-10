#!/usr/bin/env bash
# Installs crane, hadolint, actionlint and shfmt, checksum-verified (see download-lib.sh).
set -euo pipefail

BIN_DIR="/usr/bin"
# shellcheck source=download-lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/download-lib.sh"
mkdir -p "$CACHE_DIR"

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

log "Installing shfmt"
# The release has no checksum file: pin the sha256 GitHub reports for the asset, and update it with the version.
SHFMT_VERSION=v3.14.1 # renovate: datasource=github-releases depName=mvdan/sh
SHFMT_SHA256=76e77641faa025814b77f153b29796b8e6fa2fca03e0c76a691608b86c7ea7bf
SHFMT_BIN="$(tmp_name shfmt "$SHFMT_VERSION" bin)"
download_if_missing "$SHFMT_BIN" "https://github.com/mvdan/sh/releases/download/${SHFMT_VERSION}/shfmt_${SHFMT_VERSION}_linux_amd64"
echo "${SHFMT_SHA256}  shfmt" >"$work/shfmt.sum"
verify "$SHFMT_BIN" shfmt "$work/shfmt.sum"
install -o root -g root -m 0755 "$SHFMT_BIN" "$BIN_DIR/shfmt"
shfmt --version
