#!/usr/bin/env bash
set -euo pipefail

trap '[[ $BASH_COMMAND != echo* ]] && [[ $BASH_COMMAND != log* ]] && echo "+ $BASH_COMMAND"' DEBUG

log() {
    echo "=== $* ==="
}

debug() {
    echo "[DEBUG] $*" >&2
}

PLATFORM_ARCH="$(uname -m | sed 's/x86_64/amd64/; s/aarch64/arm64/')" # amd64
HOST_ARCH="$(uname -m)"                                               # x86_64
MACHINE="$(uname -s | tr '[:upper:]' '[:lower:]')"                    # linux
BIN_DIR="/usr/local/bin"
COMPLETION_DIR="/usr/local/share/bash-completion/completions"

mkdir -p "$BIN_DIR" "$COMPLETION_DIR" "/runner/cache"

setfattr -n user.component -v "utilities" /usr/local/bin
setfattr -n user.component -v "utilities" /usr/local/share/bash-completion

tmp_name() {
    # Usage: tmp_name <name> <version> <ext>
    # Normalizes version to be filesystem-safe.
    local name="$1"
    local version="$2"
    local ext="$3"
    local safe_version="${version//\//-}"
    safe_version="${safe_version// /_}"
    echo "/runner/cache/${name}-${safe_version}.${ext}"
}

download_if_missing() {
    # Usage: download_if_missing <dest> <url>
    local dest="$1"
    local url="$2"

    if [[ -f "$dest" ]]; then
        debug "Using cached $dest"
        return 0
    fi

    curl -sLo "$dest" "$url"
}

download_if_missing_cmd() {
    # Usage: download_if_missing_cmd <dest> <command...>
    # Runs the command ONLY if <dest> is missing, and expects the command to print the URL.
    local dest="$1"
    shift

    if [[ -f "$dest" ]]; then
        debug "Using cached $dest"
        return 0
    fi

    local url
    url="$("$@")"
    curl -sLo "$dest" "$url"
}

extract() {
    # Extracts the specified archive to BIN_DIR and ensures correct ownership
    local source="$1"
    shift

    case "$source" in
    *.tar.gz | *.tgz)
        tar -zxvf "$source" -C "$BIN_DIR"/ "$@" \
            --exclude=LICENSE \
            --exclude=CHANGELOG.md \
            --exclude=license \
            --exclude=licenses \
            --exclude='*.md' \
            --owner=root --group=root \
            --no-same-owner
        ;;
    *.tar.xz)
        tar -xvJf "$source" -C "$BIN_DIR"/ "$@" \
            --exclude=LICENSE \
            --exclude=CHANGELOG.md \
            --exclude=license \
            --exclude=licenses \
            --exclude='*.md' \
            --owner=root --group=root \
            --no-same-owner
        ;;
    *.tar.bz2)
        tar -xvjf "$source" -C "$BIN_DIR"/ "$@" \
            --exclude=LICENSE \
            --exclude=CHANGELOG.md \
            --exclude=license \
            --exclude=licenses \
            --exclude='*.md' \
            --owner=root --group=root \
            --no-same-owner
        ;;
    *.zip)
        unzip "$source" -d "$BIN_DIR"/ \
            -x LICENSE license licenses '*.md'
        ;;
    *)
        echo "Unsupported archive format: $source" >&2
        return 1
        ;;
    esac
}

log "Installing oh-my-bash"
mkdir -p /usr/local
bash -c "$(curl -fsSL https://raw.githubusercontent.com/ohmybash/oh-my-bash/master/tools/install.sh)" --prefix=/usr/local --unattended

log "Installing static binaries"

log "Installing age"
AGE_VERSION="v1.3.1" # renovate: datasource=github-releases depName=FiloSottile/age
AGE_TGZ="$(tmp_name age "$AGE_VERSION" tar.gz)"
download_if_missing_cmd "$AGE_TGZ" /ctx/build_files/github-release-url.sh FiloSottile/age "${MACHINE}-${PLATFORM_ARCH}.tar.gz" "$AGE_VERSION"
extract "$AGE_TGZ" --strip-components=1

log "Installing gh-cli"
GH_CLI_VERSION="v2.87.0" # renovate: datasource=github-releases depName=cli/cli
GH_CLI_TGZ="$(tmp_name gh-cli "$GH_CLI_VERSION" tar.gz)"
download_if_missing_cmd "$GH_CLI_TGZ" /ctx/build_files/github-release-url.sh cli/cli "${MACHINE}_${PLATFORM_ARCH}.tar.gz" "$GH_CLI_VERSION"
extract "$GH_CLI_TGZ" --wildcards "*/bin/*" --strip-components=2
"$BIN_DIR/gh" completion bash >"$COMPLETION_DIR/gh"

log "Installing kubectl"
KUBECTL_VERSION="v1.35.1" # renovate: datasource=github-releases depName=kubernetes/kubernetes
KUBECTL_BIN="$(tmp_name kubectl "$KUBECTL_VERSION" bin)"
download_if_missing "$KUBECTL_BIN" "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/${MACHINE}/${PLATFORM_ARCH}/kubectl"
install -o root -g root -m 0755 "$KUBECTL_BIN" "$BIN_DIR/kubectl"
"$BIN_DIR/kubectl" completion bash >"$COMPLETION_DIR/kubectl"

log "Installing kubectl-oidc-login (kubelogin)"
KUBELOGIN_VERSION="v1.35.2" # renovate: datasource=github-releases depName=int128/kubelogin
KUBELOGIN_ZIP="$(tmp_name kubelogin "$KUBELOGIN_VERSION" zip)"
download_if_missing_cmd "$KUBELOGIN_ZIP" /ctx/build_files/github-release-url.sh int128/kubelogin "${MACHINE}.${PLATFORM_ARCH}.zip" "$KUBELOGIN_VERSION"
extract "$KUBELOGIN_ZIP"
# Create symlinks so kubectl recognizes the plugin
ln -sf "$BIN_DIR/kubelogin" "$BIN_DIR/kubectl-oidc_login"
"$BIN_DIR/kubelogin" completion bash >"$COMPLETION_DIR/kubelogin"

log "Installing kubectl virt"
KUBEVIRT_VERSION="v1.7.0" # renovate: datasource=github-releases depName=kubevirt/kubectl-virt-plugin
mkdir -p /tmp/kubectl-virt
KUBEVIRT_TGZ="$(tmp_name kubectl-virt "$KUBEVIRT_VERSION" tar.gz)"
download_if_missing_cmd "$KUBEVIRT_TGZ" /ctx/build_files/github-release-url.sh kubevirt/kubectl-virt-plugin "virtctl-${MACHINE}-${PLATFORM_ARCH}.tar.gz" "$KUBEVIRT_VERSION"
tar -zxvf "$KUBEVIRT_TGZ" -C /tmp/kubectl-virt/ --strip-components=1 --exclude=LICENSE
install -o root -g root -m 0755 "/tmp/kubectl-virt/virtctl-${MACHINE}-${PLATFORM_ARCH}" "$BIN_DIR/virtctl"
# Create symlinks so kubectl recognizes the plugin
ln -sf "$BIN_DIR/virtctl" "$BIN_DIR/kubectl-virt"
"$BIN_DIR/virtctl" completion bash >"$COMPLETION_DIR/virtctl"

log "Installing kubectl-cnpg"
KUBECTLCNPG_VERSION="v1.28.1" # renovate: datasource=github-releases depName=cloudnative-pg/cloudnative-pg
KUBECTLCNPG_TGZ="$(tmp_name kubectl-cnpg "$KUBECTLCNPG_VERSION" tar.gz)"
download_if_missing_cmd "$KUBECTLCNPG_TGZ" /ctx/build_files/github-release-url.sh cloudnative-pg/cloudnative-pg "kubectl.*_${MACHINE}_${HOST_ARCH}.tar.gz" "$KUBECTLCNPG_VERSION"
extract "$KUBECTLCNPG_TGZ"
"$BIN_DIR/kubectl-cnpg" completion bash >"$COMPLETION_DIR/kubectl-cnpg"

log "Installing kind"
KIND_VERSION="v0.31.0" # renovate: datasource=github-releases depName=kubernetes-sigs/kind
KIND_BIN="$(tmp_name kind "$KIND_VERSION" bin)"
download_if_missing_cmd "$KIND_BIN" /ctx/build_files/github-release-url.sh kubernetes-sigs/kind "${MACHINE}.${PLATFORM_ARCH}" "$KIND_VERSION"
install -o root -g root -m 0755 "$KIND_BIN" "$BIN_DIR/kind"
"$BIN_DIR/kind" completion bash >"$COMPLETION_DIR/kind"

log "Installing flux"
FLUX_VERSION="v2.7.5" # renovate: datasource=github-releases depName=fluxcd/flux2
FLUX_TGZ="$(tmp_name flux "$FLUX_VERSION" tar.gz)"
download_if_missing_cmd "$FLUX_TGZ" /ctx/build_files/github-release-url.sh fluxcd/flux2 "${MACHINE}.${PLATFORM_ARCH}.tar.gz" "$FLUX_VERSION"
extract "$FLUX_TGZ"
"$BIN_DIR/flux" completion bash >"$COMPLETION_DIR/flux"

log "Installing kustomize"
KUSTOMIZE_VERSION="kustomize/v5.7.1" # renovate: datasource=github-releases depName=kubernetes-sigs/kustomize
KUSTOMIZE_TGZ="$(tmp_name kustomize "$KUSTOMIZE_VERSION" tar.gz)"
download_if_missing_cmd "$KUSTOMIZE_TGZ" /ctx/build_files/github-release-url.sh kubernetes-sigs/kustomize "${MACHINE}.${PLATFORM_ARCH}.tar.gz" "$KUSTOMIZE_VERSION"
extract "$KUSTOMIZE_TGZ"
"$BIN_DIR/kustomize" completion bash >"$COMPLETION_DIR/kustomize"

log "Installing k9s"
K9S_VERSION=v0.50.18 # renovate: datasource=github-releases depName=derailed/k9s
K9S_TGZ="$(tmp_name k9s "$K9S_VERSION" tar.gz)"
download_if_missing_cmd "$K9S_TGZ" /ctx/build_files/github-release-url.sh derailed/k9s "${MACHINE}.${PLATFORM_ARCH}.tar.gz" "$K9S_VERSION"
extract "$K9S_TGZ"
"$BIN_DIR/k9s" completion bash >"$COMPLETION_DIR/k9s"

log "Installing sops"
SOPS_VERSION=v3.11.0 # renovate: datasource=github-releases depName=getsops/sops
SOPS_BIN="$(tmp_name sops "$SOPS_VERSION" bin)"
download_if_missing_cmd "$SOPS_BIN" /ctx/build_files/github-release-url.sh getsops/sops "${MACHINE}.${PLATFORM_ARCH}" "$SOPS_VERSION"
install -o root -g root -m 0755 "$SOPS_BIN" "$BIN_DIR/sops"

log "Installing mkcert"
MKCERT_VERSION=v1.4.4 # renovate: datasource=github-releases depName=FiloSottile/mkcert
MKCERT_BIN="$(tmp_name mkcert "$MKCERT_VERSION" bin)"
download_if_missing_cmd "$MKCERT_BIN" /ctx/build_files/github-release-url.sh FiloSottile/mkcert "${MACHINE}.${PLATFORM_ARCH}" "$MKCERT_VERSION"
install -o root -g root -m 0755 "$MKCERT_BIN" "$BIN_DIR/mkcert"

log "Installing jq"
JQ_VERSION="jq-1.8.1" # renovate: datasource=github-releases depName=jqlang/jq
JQ_BIN="$(tmp_name jq "$JQ_VERSION" bin)"
download_if_missing_cmd "$JQ_BIN" /ctx/build_files/github-release-url.sh jqlang/jq "${MACHINE}.${PLATFORM_ARCH}" "$JQ_VERSION"
install -o root -g root -m 0755 "$JQ_BIN" "$BIN_DIR/jq"

log "Installing yq"
YQ_VERSION="v4.52.4" # renovate: datasource=github-releases depName=mikefarah/yq
YQ_BIN="$(tmp_name yq "$YQ_VERSION" bin)"
download_if_missing_cmd "$YQ_BIN" /ctx/build_files/github-release-url.sh mikefarah/yq "${MACHINE}.${PLATFORM_ARCH}" "$YQ_VERSION"
install -o root -g root -m 0755 "$YQ_BIN" "$BIN_DIR/yq"
"$BIN_DIR/yq" completion bash >"$COMPLETION_DIR/yq"

log "Installing cosign"
COSIGN_VERSION="v3.0.5" # renovate: datasource=github-releases depName=sigstore/cosign
COSIGN_BIN="$(tmp_name cosign "$COSIGN_VERSION" bin)"
download_if_missing_cmd "$COSIGN_BIN" /ctx/build_files/github-release-url.sh sigstore/cosign "${MACHINE}.${PLATFORM_ARCH}" "$COSIGN_VERSION"
install -o root -g root -m 0755 "$COSIGN_BIN" "$BIN_DIR/cosign"
"$BIN_DIR/cosign" completion bash >"$COMPLETION_DIR/cosign"

log "Installing shfmt"
SHFMT_VERSION="v3.12.0" # renovate: datasource=github-releases depName=mvdan/sh
SHFMT_BIN="$(tmp_name shfmt "$SHFMT_VERSION" bin)"
download_if_missing_cmd "$SHFMT_BIN" /ctx/build_files/github-release-url.sh mvdan/sh "${MACHINE}.${PLATFORM_ARCH}" "$SHFMT_VERSION"
install -o root -g root -m 0755 "$SHFMT_BIN" "$BIN_DIR/shfmt"

log "Installing talosctl"
TALOSCTL_VERSION="v1.12.4" # renovate: datasource=github-releases depName=siderolabs/talos
TALOSCTL_BIN="$(tmp_name talosctl "$TALOSCTL_VERSION" bin)"
download_if_missing_cmd "$TALOSCTL_BIN" /ctx/build_files/github-release-url.sh siderolabs/talos "talosctl-${MACHINE}.${PLATFORM_ARCH}" "$TALOSCTL_VERSION"
install -o root -g root -m 0755 "$TALOSCTL_BIN" "$BIN_DIR/talosctl"
"$BIN_DIR/talosctl" completion bash >"$COMPLETION_DIR/talosctl"

log "Installing helm"
HELM_VERSION="v4.1.1" # renovate: datasource=github-releases depName=helm/helm
HELM_TGZ="$(tmp_name helm "$HELM_VERSION" tar.gz)"
download_if_missing "$HELM_TGZ" "https://get.helm.sh/helm-${HELM_VERSION}-${MACHINE}-${PLATFORM_ARCH}.tar.gz"
extract "$HELM_TGZ" -C "$BIN_DIR"/ --strip-components=1
"$BIN_DIR/helm" completion bash >"$COMPLETION_DIR/helm"

log "Installing numr"
NUMR_VERSION="v0.4.1" # renovate: datasource=github-releases depName=nasedkinpv/numr
NUMR_TGZ="$(tmp_name numr "$NUMR_VERSION" tar.gz)"
download_if_missing_cmd "$NUMR_TGZ" /ctx/build_files/github-release-url.sh nasedkinpv/numr "${HOST_ARCH}-unknown-${MACHINE}-gnu.tar.gz" "$NUMR_VERSION"
extract "$NUMR_TGZ"

log "Installing lazyjournal"
LAZYJOURNAL_VERSION="0.8.5" # renovate: datasource=github-releases depName=Lifailon/lazyjournal
LAZYJOURNAL_BIN="$(tmp_name lazyjournal "$LAZYJOURNAL_VERSION" bin)"
download_if_missing_cmd "$LAZYJOURNAL_BIN" /ctx/build_files/github-release-url.sh Lifailon/lazyjournal "lazyjournal-${LAZYJOURNAL_VERSION}.${MACHINE}.${PLATFORM_ARCH}" "$LAZYJOURNAL_VERSION"
install -o root -g root -m 0755 "$LAZYJOURNAL_BIN" "$BIN_DIR/lazyjournal"

log "Installing lazydocker"
LAZYDOCKER_VERSION="v0.24.4" # renovate: datasource=github-releases depName=jesseduffield/lazydocker
LAZYDOCKER_TGZ="$(tmp_name lazydocker "$LAZYDOCKER_VERSION" tar.gz)"
download_if_missing_cmd "$LAZYDOCKER_TGZ" /ctx/build_files/github-release-url.sh jesseduffield/lazydocker "${MACHINE}.${HOST_ARCH}.tar.gz" "$LAZYDOCKER_VERSION"
extract "$LAZYDOCKER_TGZ"

log "Installing lazygit"
LAZYGIT_VERSION="v0.59.0" # renovate: datasource=github-releases depName=jesseduffield/lazygit
LAZYGIT_TGZ="$(tmp_name lazygit "$LAZYGIT_VERSION" tar.gz)"
download_if_missing_cmd "$LAZYGIT_TGZ" /ctx/build_files/github-release-url.sh jesseduffield/lazygit "${MACHINE}.${HOST_ARCH}.tar.gz" "$LAZYGIT_VERSION"
extract "$LAZYGIT_TGZ"

log "Installing doxx"
DOXX_VERSION="v0.1.2" # renovate: datasource=github-releases depName=bgreenwell/doxx
DOXX_TGZ="$(tmp_name doxx "$DOXX_VERSION" tar.gz)"
download_if_missing_cmd "$DOXX_TGZ" /ctx/build_files/github-release-url.sh bgreenwell/doxx "doxx-${MACHINE}.${HOST_ARCH}.tar.gz" "$DOXX_VERSION"
extract "$DOXX_TGZ"

log "Installing witr"
WITR_VERSION="v0.2.7" # renovate: datasource=github-releases depName=pranshuparmar/witr
WITR_BIN="$(tmp_name witr "$WITR_VERSION" bin)"
download_if_missing_cmd "$WITR_BIN" /ctx/build_files/github-release-url.sh pranshuparmar/witr "witr-${MACHINE}.${PLATFORM_ARCH}" "$WITR_VERSION"
install -o root -g root -m 0755 "$WITR_BIN" "$BIN_DIR/witr"

log "Installing tre"
TRE_VERSION="v0.4.0" # renovate: datasource=github-releases depName=dduan/tre
TRE_TGZ="$(tmp_name tre "$TRE_VERSION" tar.gz)"
download_if_missing_cmd "$TRE_TGZ" /ctx/build_files/github-release-url.sh dduan/tre "${HOST_ARCH}.unknown.${MACHINE}.musl.tar.gz" "$TRE_VERSION"
extract "$TRE_TGZ"

log "Installing tealdeer"
TEALDEER_VERSION="v1.8.1" # renovate: datasource=github-releases depName=tealdeer-rs/tealdeer
TEALDEER_BIN="$(tmp_name witr "$TEALDEER_VERSION" bin)"
download_if_missing_cmd "$TEALDEER_BIN" /ctx/build_files/github-release-url.sh tealdeer-rs/tealdeer "tealdeer-${MACHINE}.${HOST_ARCH}" "$TEALDEER_VERSION"
download_if_missing_cmd "${TEALDEER_BIN}_bash_tealdeer" /ctx/build_files/github-release-url.sh tealdeer-rs/tealdeer "completions_bash" "$TEALDEER_VERSION"
install -o root -g root -m 0755 "$TEALDEER_BIN" "$BIN_DIR/tldr"
cp "${TEALDEER_BIN}_bash_tealdeer" "$COMPLETION_DIR/tldr"

log "Installing fresh-editor"
FRESH_VERSION="v0.2.4" # renovate: datasource=github-releases depName=sinelaw/fresh
FRESH_TXZ="$(tmp_name fresh-editor "$FRESH_VERSION" tar.xz)"
download_if_missing_cmd "$FRESH_TXZ" /ctx/build_files/github-release-url.sh sinelaw/fresh "fresh-editor-${HOST_ARCH}-unknown-${MACHINE}-gnu.tar.xz" "$FRESH_VERSION"
extract "$FRESH_TXZ" --strip-components=1 --exclude=themes --exclude=plugins

log "Installing crane"
CRANE_VERSION=v0.21.0 # renovate: datasource=github-releases depName=google/go-containerregistry
CRANE_TGZ="$(tmp_name crane "$CRANE_VERSION" tar.gz)"
download_if_missing_cmd "$CRANE_TGZ" /ctx/build_files/github-release-url.sh google/go-containerregistry "go-containerregistry_${MACHINE}_${HOST_ARCH}.tar.gz" "$CRANE_VERSION"
extract "$CRANE_TGZ"

log "Installing dysk"
DYSK_VERSION="latest"
DYSK_BIN="$(tmp_name dysk "$DYSK_VERSION" bin)"
download_if_missing "$DYSK_BIN" "https://dystroy.org/dysk/download/${HOST_ARCH}-${MACHINE}/dysk"
install -o root -g root -m 0755 "$DYSK_BIN" "$BIN_DIR/dysk"

chmod -R 755 "$BIN_DIR"/
chmod -R 755 "$COMPLETION_DIR"/
