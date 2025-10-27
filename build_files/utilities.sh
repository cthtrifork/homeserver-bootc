#!/usr/bin/env bash
set -euo pipefail

trap '[[ $BASH_COMMAND != echo* ]] && [[ $BASH_COMMAND != log* ]] && echo "+ $BASH_COMMAND"' DEBUG

log() {
  echo "=== $* ==="
}

ARCH="amd64"
MACHINE="linux"

log "Installing oh-my-bash"
bash -c "$(curl -fsSL https://raw.githubusercontent.com/ohmybash/oh-my-bash/master/tools/install.sh)" --prefix=/usr/local --unattended

log "Installing age"
AGE_VERSION="v1.2.1" # renovate: datasource=github-releases depName=FiloSottile/age
curl -sLo /tmp/age.tar.gz \
    "$(/ctx/build_files/github-release-url.sh FiloSottile/age ${MACHINE}-${ARCH}.tar.gz $AGE_VERSION)"
tar -zxvf /tmp/age.tar.gz -C /usr/bin/ --strip-components=1 --exclude=LICENSE

log "Installing kubectl"
KUBECTL_VERSION="v1.34.1" # renovate: datasource=github-releases depName=kubernetes/kubernetes
curl -sLo /tmp/kubectl "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/${MACHINE}/${ARCH}/kubectl"
install -o root -g root -m 0755 /tmp/kubectl /usr/bin/kubectl
/usr/bin/kubectl completion bash >/etc/bash_completion.d/kubectl.sh

log "Installing kubectl-oidc-login (kubelogin)"
KUBELOGIN_VERSION="v1.34.1" # renovate: datasource=github-releases depName=int128/kubelogin
curl -sLo /tmp/kubelogin.zip \
    "$(/ctx/build_files/github-release-url.sh int128/kubelogin ${MACHINE}.${ARCH}.zip $KUBELOGIN_VERSION)"
unzip /tmp/kubelogin.zip -d /usr/bin/ -x "LICENSE" "README.md"
# Create symlinks so kubectl recognizes the plugin
ln -sf /usr/bin/kubelogin /usr/bin/kubectl-oidc_login
/usr/bin/kubelogin completion bash >/etc/bash_completion.d/kubelogin.sh

log "Installing kubectl virt"
KUBEVIRT_VERSION="v1.6.2" # renovate: datasource=github-releases depName=kubevirt/kubectl-virt-plugin
mkdir -p /tmp/kubectl-virt
curl -sLo /tmp/kubectl-virt.tar.gz \
    "$(/ctx/build_files/github-release-url.sh kubevirt/kubectl-virt-plugin virtctl-${MACHINE}-${ARCH}.tar.gz $KUBEVIRT_VERSION)"
tar -zxvf /tmp/kubectl-virt.tar.gz -C /tmp/kubectl-virt/ --strip-components=1 --exclude=LICENSE
install -o root -g root -m 0755 /tmp/kubectl-virt/virtctl-${MACHINE}-${ARCH} /usr/bin/virtctl
# Create symlinks so kubectl recognizes the plugin
ln -sf /usr/bin/virtctl /usr/bin/kubectl-virt
/usr/bin/virtctl completion bash >/etc/bash_completion.d/virtctl.sh

log "Installing kubectl-cnpg"
KUBECTLCNPG_VERSION="v1.27.0" # renovate: datasource=github-releases depName=cloudnative-pg/cloudnative-pg
curl -sLo /tmp/kubectl-cnpg.tar.gz \
    "$(/ctx/build_files/github-release-url.sh cloudnative-pg/cloudnative-pg "kubectl.*_${MACHINE}_x86_64.tar.gz" $KUBECTLCNPG_VERSION)"
tar -zxvf /tmp/kubectl-cnpg.tar.gz -C /usr/bin/ --exclude=LICENSE --exclude=README.md --exclude=licenses
/usr/bin/kubectl-cnpg completion bash >/etc/bash_completion.d/kubectl-cnpg.sh

log "Installing kind"
KIND_VERSION="v0.30.0" # renovate: datasource=github-releases depName=kubernetes-sigs/kind
curl -sLo /tmp/kind \
    "$(/ctx/build_files/github-release-url.sh kubernetes-sigs/kind ${MACHINE}.${ARCH} $KIND_VERSION)"
install -o root -g root -m 0755 /tmp/kind /usr/bin/kind
/usr/bin/kind completion bash >/etc/bash_completion.d/kind.sh

log "Installing flux"
FLUX_VERSION="v2.7.2" # renovate: datasource=github-releases depName=fluxcd/flux2
curl -sLo /tmp/flux.tar.gz \
    "$(/ctx/build_files/github-release-url.sh fluxcd/flux2 ${MACHINE}.${ARCH}.tar.gz $FLUX_VERSION)"
tar -zxvf /tmp/flux.tar.gz -C /usr/bin/ --exclude=LICENSE --exclude=README.md --exclude=licenses
/usr/bin/flux completion bash >/etc/bash_completion.d/flux.sh

log "Installing kustomize"
KUSTOMIZE_VERSION="kustomize/v5.7.1" # renovate: datasource=github-releases depName=kubernetes-sigs/kustomize
curl -sLo /tmp/kustomize.tar.gz \
    "$(/ctx/build_files/github-release-url.sh kubernetes-sigs/kustomize ${MACHINE}.${ARCH}.tar.gz $KUSTOMIZE_VERSION)"
tar -zxvf /tmp/kustomize.tar.gz -C /usr/bin/ --exclude=LICENSE --exclude=README.md --exclude=licenses
/usr/bin/kustomize completion bash >/etc/bash_completion.d/kustomize.sh

log "Installing k9s"
K9S_VERSION=v0.50.16 # renovate: datasource=github-releases depName=derailed/k9s
curl -sLo /tmp/k9s.tar.gz \
    "$(/ctx/build_files/github-release-url.sh derailed/k9s ${MACHINE}.${ARCH}.tar.gz $K9S_VERSION)"
tar -zxvf /tmp/k9s.tar.gz -C /usr/bin/ --exclude=LICENSE --exclude=README.md --exclude=licenses
/usr/bin/k9s completion bash >/etc/bash_completion.d/k9s.sh

log "Installing sops"
SOPS_VERSION=v3.11.0 # renovate: datasource=github-releases depName=getsops/sops
curl -sLo /tmp/sops \
    "$(/ctx/build_files/github-release-url.sh getsops/sops ${MACHINE}.${ARCH} $SOPS_VERSION)"
install -o root -g root -m 0755 /tmp/sops /usr/bin/sops

log "Installing mkcert"
MKCERT_VERSION=v1.4.4 # renovate: datasource=github-releases depName=FiloSottile/mkcert
curl -sLo /tmp/mkcert \
    "$(/ctx/build_files/github-release-url.sh FiloSottile/mkcert ${MACHINE}.${ARCH} $MKCERT_VERSION)"
install -o root -g root -m 0755 /tmp/mkcert /usr/bin/mkcert

log "Installing jq"
JQ_VERSION="jq-1.8.1" # renovate: datasource=github-releases depName=jqlang/jq
curl -sLo /tmp/jq \
    "$(/ctx/build_files/github-release-url.sh jqlang/jq ${MACHINE}.${ARCH} $JQ_VERSION)"
install -o root -g root -m 0755 /tmp/jq /usr/bin/jq

log "Installing yq"
YQ_VERSION="v4.48.1" # renovate: datasource=github-releases depName=mikefarah/yq
curl -sLo /tmp/yq \
    "$(/ctx/build_files/github-release-url.sh mikefarah/yq ${MACHINE}.${ARCH} $YQ_VERSION)"
install -o root -g root -m 0755 /tmp/yq /usr/bin/yq
/usr/bin/yq completion bash >/etc/bash_completion.d/yq.sh

log "Installing cosign"
COSIGN_VERSION="v2.6.1" # renovate: datasource=github-releases depName=sigstore/cosign
curl -sLo /tmp/cosign \
    "$(/ctx/build_files/github-release-url.sh sigstore/cosign ${MACHINE}.${ARCH} $COSIGN_VERSION)"
install -o root -g root -m 0755 /tmp/cosign /usr/bin/cosign
/usr/bin/cosign completion bash > /etc/bash_completion.d/cosign

log "Installing shfmt"
SHFMT_VERSION="v3.12.0" # renovate: datasource=github-releases depName=mvdan/sh
curl -sLo /tmp/shfmt \
    "$(/ctx/build_files/github-release-url.sh mvdan/sh ${MACHINE}.${ARCH} $SHFMT_VERSION)"
install -o root -g root -m 0755 /tmp/shfmt /usr/bin/shfmt

log "Installing talosctl"
TALOSCTL_VERSION="v1.11.2" # renovate: datasource=github-releases depName=siderolabs/talos
curl -sLo /tmp/talosctl \
    "$(/ctx/build_files/github-release-url.sh siderolabs/talos talosctl-${MACHINE}.${ARCH} $TALOSCTL_VERSION)"
install -o root -g root -m 0755 /tmp/talosctl /usr/bin/talosctl
/usr/bin/talosctl completion bash >/etc/bash_completion.d/talosctl.sh

log "Installing helm"
HELM_VERSION="v3.19.0" # renovate: datasource=github-releases depName=helm/helm
curl -sLo /tmp/helm.tar.gz "https://get.helm.sh/helm-${HELM_VERSION}-${MACHINE}-${ARCH}.tar.gz"
tar -zxvf /tmp/helm.tar.gz -C /usr/bin/ --strip-components=1 --exclude=LICENSE --exclude=README.md --exclude=licenses
/usr/bin/helm completion bash >/etc/bash_completion.d/helm.sh