#!/usr/bin/bash
set -x

echo "Configuring vscode extensions"

code --install-extension ms-vscode-remote.remote-containers
code --install-extension ms-vscode-remote.remote-ssh
code --install-extension ms-azuretools.vscode-containers
code --install-extension ruschaaf.extended-embedded-languages
code --install-extension mkhl.shfmt
code --install-extension redhat.vscode-yaml
