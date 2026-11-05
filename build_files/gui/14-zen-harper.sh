#!/usr/bin/env bash
set -euo pipefail

trap '[[ $BASH_COMMAND != echo* ]] && [[ $BASH_COMMAND != log* ]] && echo "+ $BASH_COMMAND"' DEBUG

log() {
    echo "=== $* ==="
}

echo "::group:: ===$(basename "$0")==="

# Force-install the Harper grammar checker add-on in Zen via enterprise policies.
# https://writewithharper.com/docs/integrations/firefox-extension
HARPER_ID="harper@writewithharper.com"
HARPER_URL="https://addons.mozilla.org/firefox/downloads/latest/private-grammar-checker-harper/latest.xpi"

# policies.json lives in <install dir>/distribution, next to the zen-bin executable.
zen_bin="$(rpm -ql zen-browser | grep -E '/zen-bin$' | head -n1)"
if [[ -z "$zen_bin" ]]; then
    echo "zen-bin not found in the zen-browser package" >&2
    exit 1
fi
dist_dir="$(dirname "$zen_bin")/distribution"
policies="$dist_dir/policies.json"

mkdir -p "$dist_dir"
[[ -f "$policies" ]] || echo '{"policies":{}}' >"$policies"

log "Adding Harper to $policies"
tmp="$(mktemp)"
jq --arg id "$HARPER_ID" --arg url "$HARPER_URL" \
    '.policies.ExtensionSettings[$id] = {install_url: $url, installation_mode: "normal_installed"}' \
    "$policies" >"$tmp"
install -m 0644 "$tmp" "$policies"
rm -f "$tmp"

echo "::endgroup::"
