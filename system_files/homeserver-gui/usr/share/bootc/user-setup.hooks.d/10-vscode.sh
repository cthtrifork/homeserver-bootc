#!/usr/bin/bash

set -x

# Setup VSCode
if test ! -e "$HOME"/.config/Code/User/settings.json; then
	mkdir -p "$HOME"/.config/Code/User
	cp -f /etc/skel/.config/Code/User/settings.json "$HOME"/.config/Code/User/settings.json
fi

code --install-extension ms-vscode-remote.remote-containers
code --install-extension ms-vscode-remote.remote-ssh
code --install-extension ms-azuretools.vscode-containers
code --install-extension ruschaaf.extended-embedded-languages
code --install-extension mkhl.shfmt
code --install-extension redhat.vscode-yaml