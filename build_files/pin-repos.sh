#!/usr/bin/bash
# Pin the Fedora and RPM Fusion repositories to one mirror for the build, then restore the metalinks.
# The metalinks redirect to whichever mirror answers, so the CI runner's egress allowlist could not name them.
# Usage: pin-repos.sh pin|unpin   (pin is idempotent; call it again after files in /etc/yum.repos.d are replaced)
set -euo pipefail

FEDORA_MIRROR="https://mirrors.dotsrc.org/fedora"
RPMFUSION_HOST="download1.rpmfusion.org"
DIR=/etc/yum.repos.d

[[ $# -eq 1 ]] || { echo "Usage: ${0##*/} pin|unpin" >&2; exit 2; }

fedora=("$DIR"/fedora.repo "$DIR"/fedora-updates.repo "$DIR"/fedora-updates-testing.repo)
rpmfusion=("$DIR"/rpmfusion-*.repo)

changed() {
    # Fail instead of silently building against random mirrors
    grep -qE "^baseurl=($FEDORA_MIRROR|https://$RPMFUSION_HOST)" "${fedora[@]}" "${rpmfusion[@]}" 2>/dev/null
}

case "$1" in
pin)
    for f in "${fedora[@]}"; do
        [[ -f $f ]] || continue
        sed -i -e 's|^metalink=|#metalink=|' \
            -e "s|^#baseurl=http://download.example/pub/fedora/|baseurl=$FEDORA_MIRROR/|" "$f"
    done
    for f in "${rpmfusion[@]}"; do
        [[ -f $f ]] || continue
        sed -i -e 's|^metalink=|#metalink=|' \
            -e "s|^#baseurl=http://$RPMFUSION_HOST/|baseurl=https://$RPMFUSION_HOST/|" "$f"
    done
    changed || { echo "pin-repos: no repository was pinned" >&2; exit 1; }
    ;;
unpin)
    for f in "${fedora[@]}" "${rpmfusion[@]}"; do
        [[ -f $f ]] || continue
        sed -i -e 's|^#metalink=|metalink=|' \
            -e "s|^baseurl=$FEDORA_MIRROR/|#baseurl=http://download.example/pub/fedora/|" \
            -e "s|^baseurl=https://$RPMFUSION_HOST/|#baseurl=http://$RPMFUSION_HOST/|" "$f"
    done
    ;;
*)
    echo "Usage: ${0##*/} pin|unpin" >&2
    exit 2
    ;;
esac
