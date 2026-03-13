#!/usr/bin/env bash
set -e

trap '[[ $BASH_COMMAND != echo* ]] && [[ $BASH_COMMAND != log* ]] && echo "+ $BASH_COMMAND"' DEBUG

log() {
    echo "=== $* ==="
}

debug() {
    echo "[DEBUG] $*" >&2
}

REPO="traiproject/yaml-schema-router"
PROJECT_NAME="yaml-schema-router"

platform="$(uname -s)" # Linux
arch="$(uname -m)"     # x86_64

YAML_SCHEMA_ROUTER_VERSION="0.2.0" # renovate: datasource=github-releases depName=traiproject/yaml-schema-router

# Construct file name based on your .goreleaser.yaml template
# e.g., yaml-schema-router_v1.0.0_linux_x86_64.tar.gz
TAR_FILE="${PROJECT_NAME}_${YAML_SCHEMA_ROUTER_VERSION#v}_${OS_NAME}_${ARCH_NAME}.tar.gz"
DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${YAML_SCHEMA_ROUTER_VERSION}/${TAR_FILE}"

TMP_DIR=$(mktemp -d)
log "Downloading ${PROJECT_NAME} ${YAML_SCHEMA_ROUTER_VERSION} for ${OS_NAME} ${ARCH_NAME}..."
curl -sL "${DOWNLOAD_URL}" -o "${TMP_DIR}/${TAR_FILE}"

debug "Extracting..."
tar -xzf "${TMP_DIR}/${TAR_FILE}" -C "${TMP_DIR}"

INSTALL_DIR="/usr/local/bin"

debug "Installing to ${INSTALL_DIR}..."
mv "${TMP_DIR}/${PROJECT_NAME}" "${INSTALL_DIR}/${PROJECT_NAME}"
chmod +x "${INSTALL_DIR}/${PROJECT_NAME}"

# Clean up
rm -rf "${TMP_DIR}"

debug ""
log "Successfully installed ${PROJECT_NAME} ${YAML_SCHEMA_ROUTER_VERSION} to ${INSTALL_DIR}!"
