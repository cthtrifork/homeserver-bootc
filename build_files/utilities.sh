#!/usr/bin/env bash
set -euo pipefail

trap '[[ $BASH_COMMAND != echo* ]] && [[ $BASH_COMMAND != log* ]] && echo "+ $BASH_COMMAND"' DEBUG

log() {
    echo "=== $* ==="
}

ARCH="amd64"
MACHINE="linux"
BIN_DIR="/usr/local/bin"
COMPLETION_DIR="/usr/local/share/bash-completion/completions"

mkdir -p "$BIN_DIR" "$COMPLETION_DIR"

setfattr -n user.component -v "utilities" /usr/local/bin
setfattr -n user.component -v "utilities" /usr/local/share/bash-completion

log "Installing oh-my-bash"
mkdir -p /usr/local
bash -c "$(curl -fsSL https://raw.githubusercontent.com/ohmybash/oh-my-bash/master/tools/install.sh)" --prefix=/usr/local --unattended

log "Installing age"
AGE_VERSION="v1.2.1" # renovate: datasource=github-releases depName=FiloSottile/age
curl -sLo /tmp/age.tar.gz \
    "$(/ctx/build_files/github-release-url.sh FiloSottile/age ${MACHINE}-${ARCH}.tar.gz $AGE_VERSION)"
tar -zxvf /tmp/age.tar.gz -C "$BIN_DIR"/ --strip-components=1 --exclude=LICENSE

log "Installing gh-cli"
GH_CLI_VERSION="v2.83.2" # renovate: datasource=github-releases depName=cli/cli
curl -sLo /tmp/gh-cli.tar.gz \
    "$(/ctx/build_files/github-release-url.sh cli/cli ${MACHINE}_${ARCH}.tar.gz $GH_CLI_VERSION)"
tar -zxvf /tmp/gh-cli.tar.gz -C "$BIN_DIR"/ --wildcards "*/bin/*" --strip-components=2 --exclude=LICENSE --exclude=README.md --exclude=licenses
"$BIN_DIR/gh" completion bash >"$COMPLETION_DIR/gh"

log "Installing kubectl"
KUBECTL_VERSION="v1.34.3" # renovate: datasource=github-releases depName=kubernetes/kubernetes
curl -sLo /tmp/kubectl "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/${MACHINE}/${ARCH}/kubectl"
install -o root -g root -m 0755 /tmp/kubectl "$BIN_DIR/kubectl"
"$BIN_DIR/kubectl" completion bash >"$COMPLETION_DIR/kubectl"

log "Installing kubectl-oidc-login (kubelogin)"
KUBELOGIN_VERSION="v1.35.0" # renovate: datasource=github-releases depName=int128/kubelogin
curl -sLo /tmp/kubelogin.zip \
    "$(/ctx/build_files/github-release-url.sh int128/kubelogin ${MACHINE}.${ARCH}.zip $KUBELOGIN_VERSION)"
unzip /tmp/kubelogin.zip -d "$BIN_DIR"/ -x "LICENSE" "README.md"
# Create symlinks so kubectl recognizes the plugin
ln -sf "$BIN_DIR/kubelogin" "$BIN_DIR/kubectl-oidc_login"
"$BIN_DIR/kubelogin" completion bash >"$COMPLETION_DIR/kubelogin"

log "Installing kubectl virt"
KUBEVIRT_VERSION="v1.7.0" # renovate: datasource=github-releases depName=kubevirt/kubectl-virt-plugin
mkdir -p /tmp/kubectl-virt
curl -sLo /tmp/kubectl-virt.tar.gz \
    "$(/ctx/build_files/github-release-url.sh kubevirt/kubectl-virt-plugin virtctl-${MACHINE}-${ARCH}.tar.gz $KUBEVIRT_VERSION)"
tar -zxvf /tmp/kubectl-virt.tar.gz -C /tmp/kubectl-virt/ --strip-components=1 --exclude=LICENSE
install -o root -g root -m 0755 "/tmp/kubectl-virt/virtctl-${MACHINE}-${ARCH}" "$BIN_DIR/virtctl"
# Create symlinks so kubectl recognizes the plugin
ln -sf "$BIN_DIR/virtctl" "$BIN_DIR/kubectl-virt"
"$BIN_DIR/virtctl" completion bash >"$COMPLETION_DIR/virtctl"

log "Installing kubectl-cnpg"
KUBECTLCNPG_VERSION="v1.28.0" # renovate: datasource=github-releases depName=cloudnative-pg/cloudnative-pg
curl -sLo /tmp/kubectl-cnpg.tar.gz \
    "$(/ctx/build_files/github-release-url.sh cloudnative-pg/cloudnative-pg "kubectl.*_${MACHINE}_x86_64.tar.gz" $KUBECTLCNPG_VERSION)"
tar -zxvf /tmp/kubectl-cnpg.tar.gz -C "$BIN_DIR"/ --exclude=LICENSE --exclude=README.md --exclude=licenses
"$BIN_DIR/kubectl-cnpg" completion bash >"$COMPLETION_DIR/kubectl-cnpg"

log "Installing kind"
KIND_VERSION="v0.31.0" # renovate: datasource=github-releases depName=kubernetes-sigs/kind
curl -sLo /tmp/kind \
    "$(/ctx/build_files/github-release-url.sh kubernetes-sigs/kind ${MACHINE}.${ARCH} $KIND_VERSION)"
install -o root -g root -m 0755 /tmp/kind "$BIN_DIR/kind"
"$BIN_DIR/kind" completion bash >"$COMPLETION_DIR/kind"

log "Installing flux"
FLUX_VERSION="v2.7.5" # renovate: datasource=github-releases depName=fluxcd/flux2
curl -sLo /tmp/flux.tar.gz \
    "$(/ctx/build_files/github-release-url.sh fluxcd/flux2 ${MACHINE}.${ARCH}.tar.gz $FLUX_VERSION)"
tar -zxvf /tmp/flux.tar.gz -C "$BIN_DIR"/ --exclude=LICENSE --exclude=README.md --exclude=licenses
"$BIN_DIR/flux" completion bash >"$COMPLETION_DIR/flux"

log "Installing kustomize"
KUSTOMIZE_VERSION="kustomize/v5.7.1" # renovate: datasource=github-releases depName=kubernetes-sigs/kustomize
curl -sLo /tmp/kustomize.tar.gz \
    "$(/ctx/build_files/github-release-url.sh kubernetes-sigs/kustomize ${MACHINE}.${ARCH}.tar.gz $KUSTOMIZE_VERSION)"
tar -zxvf /tmp/kustomize.tar.gz -C "$BIN_DIR"/ --exclude=LICENSE --exclude=README.md --exclude=licenses
"$BIN_DIR/kustomize" completion bash >"$COMPLETION_DIR/kustomize"

log "Installing k9s"
K9S_VERSION=v0.50.16 # renovate: datasource=github-releases depName=derailed/k9s
curl -sLo /tmp/k9s.tar.gz \
    "$(/ctx/build_files/github-release-url.sh derailed/k9s ${MACHINE}.${ARCH}.tar.gz $K9S_VERSION)"
tar -zxvf /tmp/k9s.tar.gz -C "$BIN_DIR"/ --exclude=LICENSE --exclude=README.md --exclude=licenses
"$BIN_DIR/k9s" completion bash >"$COMPLETION_DIR/k9s"

log "Installing sops"
SOPS_VERSION=v3.11.0 # renovate: datasource=github-releases depName=getsops/sops
curl -sLo /tmp/sops \
    "$(/ctx/build_files/github-release-url.sh getsops/sops ${MACHINE}.${ARCH} $SOPS_VERSION)"
install -o root -g root -m 0755 /tmp/sops "$BIN_DIR/sops"

log "Installing mkcert"
MKCERT_VERSION=v1.4.4 # renovate: datasource=github-releases depName=FiloSottile/mkcert
curl -sLo /tmp/mkcert \
    "$(/ctx/build_files/github-release-url.sh FiloSottile/mkcert ${MACHINE}.${ARCH} $MKCERT_VERSION)"
install -o root -g root -m 0755 /tmp/mkcert "$BIN_DIR/mkcert"

log "Installing jq"
JQ_VERSION="jq-1.8.1" # renovate: datasource=github-releases depName=jqlang/jq
curl -sLo /tmp/jq \
    "$(/ctx/build_files/github-release-url.sh jqlang/jq ${MACHINE}.${ARCH} $JQ_VERSION)"
install -o root -g root -m 0755 /tmp/jq "$BIN_DIR/jq"

log "Installing yq"
YQ_VERSION="v4.50.1" # renovate: datasource=github-releases depName=mikefarah/yq
curl -sLo /tmp/yq \
    "$(/ctx/build_files/github-release-url.sh mikefarah/yq ${MACHINE}.${ARCH} $YQ_VERSION)"
install -o root -g root -m 0755 /tmp/yq "$BIN_DIR/yq"
"$BIN_DIR/yq" completion bash >"$COMPLETION_DIR/yq"

log "Installing cosign"
COSIGN_VERSION="v3.0.3" # renovate: datasource=github-releases depName=sigstore/cosign
curl -sLo /tmp/cosign \
    "$(/ctx/build_files/github-release-url.sh sigstore/cosign ${MACHINE}.${ARCH} $COSIGN_VERSION)"
install -o root -g root -m 0755 /tmp/cosign "$BIN_DIR/cosign"
"$BIN_DIR/cosign" completion bash >"$COMPLETION_DIR/cosign"

log "Installing shfmt"
SHFMT_VERSION="v3.12.0" # renovate: datasource=github-releases depName=mvdan/sh
curl -sLo /tmp/shfmt \
    "$(/ctx/build_files/github-release-url.sh mvdan/sh ${MACHINE}.${ARCH} $SHFMT_VERSION)"
install -o root -g root -m 0755 /tmp/shfmt "$BIN_DIR/shfmt"

log "Installing talosctl"
TALOSCTL_VERSION="v1.11.6" # renovate: datasource=github-releases depName=siderolabs/talos
curl -sLo /tmp/talosctl \
    "$(/ctx/build_files/github-release-url.sh siderolabs/talos talosctl-${MACHINE}.${ARCH} $TALOSCTL_VERSION)"
install -o root -g root -m 0755 /tmp/talosctl "$BIN_DIR/talosctl"
"$BIN_DIR/talosctl" completion bash >"$COMPLETION_DIR/talosctl"

log "Installing helm"
HELM_VERSION="v3.19.4" # renovate: datasource=github-releases depName=helm/helm
curl -sLo /tmp/helm.tar.gz "https://get.helm.sh/helm-${HELM_VERSION}-${MACHINE}-${ARCH}.tar.gz"
tar -zxvf /tmp/helm.tar.gz -C "$BIN_DIR"/ --strip-components=1 --exclude=LICENSE --exclude=README.md --exclude=licenses
"$BIN_DIR/helm" completion bash >"$COMPLETION_DIR/helm"

log "Installing dysk"
curl -sLo /tmp/dysk https://dystroy.org/dysk/download/x86_64-linux/dysk
install -o root -g root -m 0755 /tmp/dysk "$BIN_DIR/dysk"

chmod -R 755 $BIN_DIR/
chmod -R 755 $COMPLETION_DIR/
