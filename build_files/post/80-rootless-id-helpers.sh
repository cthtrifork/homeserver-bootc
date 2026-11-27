#!/usr/bin/bash

echo "::group:: ===$(basename "$0")==="

set -ouex pipefail

# Rootless podman needs newuidmap/newgidmap privileged. File capabilities are an xattr that chown or a layer copy can
# drop; the setuid bit survives that.
rpm --setugids --setperms --setcaps shadow-utils
chown root:root /usr/bin/newuidmap /usr/bin/newgidmap
chmod 4755 /usr/bin/newuidmap /usr/bin/newgidmap

for f in /usr/bin/newuidmap /usr/bin/newgidmap; do
    [[ "$(stat -c '%u:%g %a' "$f")" == "0:0 4755" ]] || {
        echo "$f must be root:root 4755" >&2
        exit 1
    }
done

echo "::endgroup::"
