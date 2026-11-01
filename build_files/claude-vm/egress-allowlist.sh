#!/usr/bin/bash
# Image build step: validate the egress allowlist and derive everything that consumes it.
#   usage: egress-allowlist.sh ALLOWLIST MANAGED_SETTINGS_JSON OUTDIR
#   - fails the build on an invalid, duplicate or redundant entry (e.g. api.github.com next to github.com)
#   - sets .sandbox.network.allowedDomains in MANAGED_SETTINGS_JSON ("d" and "*.d" for every entry)
#   - writes OUTDIR/nginx-allow.map and OUTDIR/dnsmasq-servers (included by the static gateway configs) and
#     OUTDIR/allowlist.txt (the normalized list)
set -euo pipefail

[[ $# -eq 3 ]] || { echo "usage: ${0##*/} ALLOWLIST MANAGED_SETTINGS_JSON OUTDIR" >&2; exit 2; }
list="$1" settings="$2" out="$3"
resolver=127.0.0.53   # systemd-resolved stub; the proxy and dnsmasq are not subject to the agent's firewall rules

label='[a-z0-9]([a-z0-9-]*[a-z0-9])?'
domain_re="^${label}(\\.${label})+\$"
numeric_re='^[0-9.]+$'   # IPv4 literals are not hostnames

mapfile -t domains < <(sed -e 's/#.*//' -e 's/[[:space:]]*$//' -e 's/^[[:space:]]*//' -e '/^$/d' "$list")
[[ ${#domains[@]} -gt 0 ]] || { echo "$list: empty allowlist" >&2; exit 1; }

declare -A seen=()
errors=0
fail() { echo "$list: $*" >&2; errors=1; }
for d in "${domains[@]}"; do
    if ! [[ $d =~ $domain_re ]] || [[ $d =~ $numeric_re ]]; then
        fail "invalid entry '$d' (lowercase hostname without wildcard, port or path)"
    elif [[ -n ${seen[$d]:-} ]]; then
        fail "duplicate entry '$d'"
    fi
    seen[$d]=1
done
for d in "${domains[@]}"; do
    parent="$d"
    while [[ $parent == *.* ]]; do
        parent="${parent#*.}"
        [[ -z ${seen[$parent]:-} ]] || fail "'$d' is already covered by '$parent'"
    done
done
[[ $errors -eq 0 ]] || exit 1

mapfile -t sorted < <(printf '%s\n' "${domains[@]}" | sort)
install -d -m 0755 "$out"
printf '%s\n' "${sorted[@]}" >"$out/allowlist.txt"
printf '.%s  1;\n' "${sorted[@]}" >"$out/nginx-allow.map"
for d in "${sorted[@]}"; do echo "server=/$d/$resolver"; done >"$out/dnsmasq-servers"

tmp="$(mktemp)"
printf '%s\n' "${sorted[@]}" |
    jq -R -s --slurpfile s "$settings" 'split("\n") | map(select(. != "")) | map(., "*." + .) as $d | $s[0] | .sandbox.network.allowedDomains = $d' \
    >"$tmp"
cat "$tmp" >"$settings"
rm -f "$tmp"

echo "egress-allowlist: ${#sorted[@]} domains"
