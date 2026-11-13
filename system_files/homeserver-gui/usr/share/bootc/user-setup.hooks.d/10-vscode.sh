#!/usr/bin/bash
set -x

echo "Configuring vscode extensions"

extensions=(
    ms-vscode-remote.remote-containers
    ms-vscode-remote.remote-ssh
    ms-azuretools.vscode-containers
    ruschaaf.extended-embedded-languages
    mkhl.shfmt
    redhat.vscode-yaml
)

# This hook runs on every boot and blocks multi-user.target, so only install what is missing:
# each `code --install-extension` is a slow, network-bound call. If listing fails, install everything.
if ! installed="$(code --list-extensions 2>/dev/null)"; then
    # a failed listing may still have printed some IDs; do not treat that as authoritative
    installed=""
fi
echo "extensions reported by code: $(grep -c . <<<"$installed" || true)"
for ext in "${extensions[@]}"; do
    if grep -qixF "$ext" <<<"$installed"; then
        echo "already installed: $ext"
        continue
    fi
    code --install-extension "$ext"
done
