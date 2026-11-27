#!/usr/bin/env bash
# Installs iron-proxy (the egress gateway), crane, hadolint, actionlint, shfmt, kubectl, helm, kustomize, kubeconform and flux-schema, checksum-verified (see download-lib.sh).
set -euo pipefail

BIN_DIR="/usr/bin"
# shellcheck source=download-lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/download-lib.sh"
mkdir -p "$CACHE_DIR"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

log "Installing iron-proxy"
# The egress gateway. Under /usr/libexec (bin_t, so it runs unconfined and may connect upstream), next to the other claude-vm helpers.
IRON_PROXY_VERSION=v0.61.0 # renovate: datasource=github-releases depName=paradigmxyz/iron-proxy
ver="${IRON_PROXY_VERSION#v}"
IRON_PROXY_TGZ="$(tmp_name iron-proxy "$IRON_PROXY_VERSION" tar.gz)"
base="https://github.com/paradigmxyz/iron-proxy/releases/download/${IRON_PROXY_VERSION}"
download_if_missing "$IRON_PROXY_TGZ" "${base}/iron-proxy_${ver}_linux_amd64.tar.gz"
fetch "$work/iron-proxy.sum" "${base}/checksums.txt"
verify "$IRON_PROXY_TGZ" "iron-proxy_${ver}_linux_amd64.tar.gz" "$work/iron-proxy.sum"
mkdir -p "$work/iron-proxy" /usr/libexec/claude-vm
tar -xzf "$IRON_PROXY_TGZ" -C "$work/iron-proxy" iron-proxy
install -o root -g root -m 0755 "$work/iron-proxy/iron-proxy" /usr/libexec/claude-vm/egress-proxy

log "Installing crane"
CRANE_VERSION=v0.22.1 # renovate: datasource=github-releases depName=google/go-containerregistry
CRANE_TGZ="$(tmp_name crane "$CRANE_VERSION" tar.gz)"
base="https://github.com/google/go-containerregistry/releases/download/${CRANE_VERSION}"
download_if_missing "$CRANE_TGZ" "${base}/go-containerregistry_Linux_x86_64.tar.gz"
fetch "$work/crane.sum" "${base}/checksums.txt"
verify "$CRANE_TGZ" go-containerregistry_Linux_x86_64.tar.gz "$work/crane.sum"
tar -xzf "$CRANE_TGZ" -C "$BIN_DIR" crane

log "Installing hadolint"
HADOLINT_VERSION=v2.15.1 # renovate: datasource=github-releases depName=hadolint/hadolint
HADOLINT_BIN="$(tmp_name hadolint "$HADOLINT_VERSION" bin)"
base="https://github.com/hadolint/hadolint/releases/download/${HADOLINT_VERSION}"
download_if_missing "$HADOLINT_BIN" "${base}/hadolint-linux-x86_64"
fetch "$work/hadolint.sum" "${base}/checksums.sha256"
verify "$HADOLINT_BIN" hadolint-linux-x86_64 "$work/hadolint.sum"
install -o root -g root -m 0755 "$HADOLINT_BIN" "$BIN_DIR/hadolint"

log "Installing actionlint"
ACTIONLINT_VERSION=v1.7.12 # renovate: datasource=github-releases depName=rhysd/actionlint
ver="${ACTIONLINT_VERSION#v}"
ACTIONLINT_TGZ="$(tmp_name actionlint "$ACTIONLINT_VERSION" tar.gz)"
base="https://github.com/rhysd/actionlint/releases/download/${ACTIONLINT_VERSION}"
download_if_missing "$ACTIONLINT_TGZ" "${base}/actionlint_${ver}_linux_amd64.tar.gz"
fetch "$work/actionlint.sum" "${base}/actionlint_${ver}_checksums.txt"
verify "$ACTIONLINT_TGZ" "actionlint_${ver}_linux_amd64.tar.gz" "$work/actionlint.sum"
tar -xzf "$ACTIONLINT_TGZ" -C "$BIN_DIR" actionlint

log "Installing shfmt"
# The release has no checksum file: pin the sha256 GitHub reports for the asset, and update it with the version.
SHFMT_VERSION=v3.14.1 # renovate: datasource=github-releases depName=mvdan/sh
SHFMT_SHA256=76e77641faa025814b77f153b29796b8e6fa2fca03e0c76a691608b86c7ea7bf
SHFMT_BIN="$(tmp_name shfmt "$SHFMT_VERSION" bin)"
download_if_missing "$SHFMT_BIN" "https://github.com/mvdan/sh/releases/download/${SHFMT_VERSION}/shfmt_${SHFMT_VERSION}_linux_amd64"
echo "${SHFMT_SHA256}  shfmt" >"$work/shfmt.sum"
verify "$SHFMT_BIN" shfmt "$work/shfmt.sum"
install -o root -g root -m 0755 "$SHFMT_BIN" "$BIN_DIR/shfmt"

log "Installing kubectl"
# Keep within one minor version of the cluster. dl.k8s.io publishes a bare sha256 file (no file name in it).
KUBECTL_VERSION=v1.37.2 # renovate: datasource=github-releases depName=kubernetes/kubernetes
KUBECTL_BIN="$(tmp_name kubectl "$KUBECTL_VERSION" bin)"
base="https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64"
download_if_missing "$KUBECTL_BIN" "${base}/kubectl"
fetch "$work/kubectl.sha256" "${base}/kubectl.sha256"
echo "$(cat "$work/kubectl.sha256")  kubectl" >"$work/kubectl.sum"
verify "$KUBECTL_BIN" kubectl "$work/kubectl.sum"
install -o root -g root -m 0755 "$KUBECTL_BIN" "$BIN_DIR/kubectl"

log "Installing helm"
HELM_VERSION=v4.3.2 # renovate: datasource=github-releases depName=helm/helm
HELM_TGZ="$(tmp_name helm "$HELM_VERSION" tar.gz)"
helm_tarball="helm-${HELM_VERSION}-linux-amd64.tar.gz"
download_if_missing "$HELM_TGZ" "https://get.helm.sh/${helm_tarball}"
fetch "$work/helm.sum" "https://get.helm.sh/${helm_tarball}.sha256sum"
verify "$HELM_TGZ" "$helm_tarball" "$work/helm.sum"
tar -xzf "$HELM_TGZ" -C "$BIN_DIR" --strip-components=1 linux-amd64/helm

log "Installing kustomize"
# The release tag contains a slash (kustomize/v...), so it is URL-encoded in the download path.
KUSTOMIZE_VERSION=5.8.3 # renovate: datasource=github-releases depName=kubernetes-sigs/kustomize extractVersion=^kustomize/v(?<version>.+)$
KUSTOMIZE_TGZ="$(tmp_name kustomize "$KUSTOMIZE_VERSION" tar.gz)"
base="https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv${KUSTOMIZE_VERSION}"
download_if_missing "$KUSTOMIZE_TGZ" "${base}/kustomize_v${KUSTOMIZE_VERSION}_linux_amd64.tar.gz"
fetch "$work/kustomize.sum" "${base}/checksums.txt"
verify "$KUSTOMIZE_TGZ" "kustomize_v${KUSTOMIZE_VERSION}_linux_amd64.tar.gz" "$work/kustomize.sum"
tar -xzf "$KUSTOMIZE_TGZ" -C "$BIN_DIR" kustomize

log "Installing kubeconform"
KUBECONFORM_VERSION=v0.8.0 # renovate: datasource=github-releases depName=yannh/kubeconform
KUBECONFORM_TGZ="$(tmp_name kubeconform "$KUBECONFORM_VERSION" tar.gz)"
base="https://github.com/yannh/kubeconform/releases/download/${KUBECONFORM_VERSION}"
download_if_missing "$KUBECONFORM_TGZ" "${base}/kubeconform-linux-amd64.tar.gz"
fetch "$work/kubeconform.sum" "${base}/CHECKSUMS"
verify "$KUBECONFORM_TGZ" kubeconform-linux-amd64.tar.gz "$work/kubeconform.sum"
tar -xzf "$KUBECONFORM_TGZ" -C "$BIN_DIR" kubeconform

log "Installing flux-schema"
# Validates Kubernetes and Flux manifests against the built-in schema catalog, so it works without cluster access or network.
FLUX_SCHEMA_VERSION=v0.18.0 # renovate: datasource=github-releases depName=fluxcd/flux-schema
ver="${FLUX_SCHEMA_VERSION#v}"
FLUX_SCHEMA_TGZ="$(tmp_name flux-schema "$FLUX_SCHEMA_VERSION" tar.gz)"
base="https://github.com/fluxcd/flux-schema/releases/download/${FLUX_SCHEMA_VERSION}"
download_if_missing "$FLUX_SCHEMA_TGZ" "${base}/flux-schema_${ver}_linux_amd64.tar.gz"
fetch "$work/flux-schema.sum" "${base}/flux-schema_${ver}_checksums.txt"
verify "$FLUX_SCHEMA_TGZ" "flux-schema_${ver}_linux_amd64.tar.gz" "$work/flux-schema.sum"
tar -xzf "$FLUX_SCHEMA_TGZ" -C "$BIN_DIR" flux-schema
