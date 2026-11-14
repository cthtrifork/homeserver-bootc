#!/usr/bin/bash

echo "::group:: ===$(basename "$0")==="

set -ouex pipefail

# VSCode package from Microsoft repo
echo "Installing VSCode from official repo..."
tee /etc/yum.repos.d/vscode.repo <<'EOF'
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF
sed -i "s/enabled=.*/enabled=0/g" /etc/yum.repos.d/vscode.repo
# openssl3-libs: Fedora 45 ships OpenSSL 4, which the bundled .NET signature verifier of VS Code (vsce-sign) cannot load;
# it aborts with SIGABRT and every extension install fails with 'Signature verification failed with UnknownError'.
dnf -y install --enablerepo=code \
    code \
    openssl3-libs

# The extensions come with the image: installed here into a system directory that VS Code is pointed at by
# VSCODE_EXTENSIONS (system_files/homeserver-gui/etc/environment.d/50-vscode.conf). Updates arrive with the image, like
# VS Code and Zed (extensions.autoUpdate is off). As root, code needs its own user data directory and --no-sandbox.
EXTENSIONS_DIR=/usr/share/vscode-extensions
extensions=(
    ms-vscode-remote.remote-containers
    ms-vscode-remote.remote-ssh
    ms-azuretools.vscode-containers
    ruschaaf.extended-embedded-languages
    mkhl.shfmt
    redhat.vscode-yaml
)
mkdir -p "$EXTENSIONS_DIR"
for ext in "${extensions[@]}"; do
    # the marketplace can fail a request; retry before failing the build
    for attempt in 1 2 3; do
        code --no-sandbox --user-data-dir /tmp/vscode-build-data --extensions-dir "$EXTENSIONS_DIR" \
            --install-extension "$ext" && break
        [ "$attempt" -lt 3 ] || {
            echo "could not install $ext"
            exit 1
        }
        sleep 10
    done
done
rm -rf /tmp/vscode-build-data
chmod -R a+rX "$EXTENSIONS_DIR"
code --no-sandbox --user-data-dir /tmp/vscode-build-data --extensions-dir "$EXTENSIONS_DIR" --list-extensions --show-versions
rm -rf /tmp/vscode-build-data

echo "::endgroup::"
