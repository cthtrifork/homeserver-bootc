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

echo "::endgroup::"