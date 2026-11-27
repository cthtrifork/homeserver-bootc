#!/usr/bin/bash

echo "::group:: ===$(basename "$0")==="

set -ouex pipefail

# Rootless podman (the trivy-scanner talks to its socket) needs newuidmap/newgidmap to run with CAP_SETUID/CAP_SETGID.
# Fedora ships them with file capabilities, which are an xattr: a chown/chgrp, or any layer or copy step that drops
# xattrs, silently removes them and every `podman run` then fails with "newuidmap: write to uid_map failed: Operation
# not permitted". Restore the whole shadow-utils package (a bad group/mode was seen on all of its files), then make
# the two helpers setuid root as well: the mode bit survives where the xattr does not.
rpm --setugids --setperms --setcaps shadow-utils
chown root:root /usr/bin/newuidmap /usr/bin/newgidmap
chmod 4755 /usr/bin/newuidmap /usr/bin/newgidmap

# Fail the build instead of shipping an image where rootless containers cannot start.
for f in /usr/bin/newuidmap /usr/bin/newgidmap; do
    [[ "$(stat -c '%u:%g %a' "$f")" == "0:0 4755" ]] || {
        echo "$f must be root:root 4755" >&2
        exit 1
    }
done

echo "::endgroup::"
