#!/bin/bash
#
# A script to print the URL of an asset from latest github release.
#

ORG_PROJ=${1}
ARCH_FILTER=${2}
GH_VERSION=${3}

debug() {
    echo "[DEBUG] $*" >&2
}

usage() {
    echo "$0 ORG_PROJ ARCH_FILTER [GH_VERSION]"
    echo "    ORG_PROJ     - organization/projectname"
    echo "    ARCH_FILTER  - filter to select the asset (regex, case-insensitive)"
    echo "    GH_VERSION   - optional tag override (e.g. v1.2.3, nightly-dev)"
}

if [[ -z "${ORG_PROJ}" ]]; then
    usage
    exit 1
fi

if [[ -z "${ARCH_FILTER}" ]]; then
    usage
    exit 2
fi

if [[ -z "${GH_VERSION}" ]]; then
    RELTAG="latest"
else
    RELTAG="tags/${GH_VERSION}"
fi

debug "ORG_PROJ=${ORG_PROJ}"
debug "ARCH_FILTER=${ARCH_FILTER}"
debug "GH_VERSION=${GH_VERSION:-<none>}"
debug "Resolved RELTAG=${RELTAG}"

set ${SET_X:+-x} -euo pipefail

API_JSON=$(mktemp /tmp/api-XXXXXXXX.json)
API="https://api.github.com/repos/${ORG_PROJ}/releases/${RELTAG}"

debug "GitHub API URL=${API}"
debug "Temporary JSON file=${API_JSON}"

# Unauthenticated API requests are limited to 60 per hour per IP address, and one image build makes about 30 of them from
# the same address as every other runner, so builds failed with curl exit 22 once the limit was used up. Send the
# build's GitHub token (the registry_token secret) when it is mounted: 5000 per hour. The token goes through a header
# file, not the command line.
AUTH_ARGS=()
TOKEN_FILE="${GITHUB_TOKEN_FILE:-/run/secrets/registry_token}"
if [[ -s "${TOKEN_FILE}" ]]; then
    AUTH_HEADER=$(mktemp /tmp/gh-auth-XXXXXXXX)
    trap 'rm -f "${AUTH_HEADER}"' EXIT
    chmod 600 "${AUTH_HEADER}"
    {
        printf 'Authorization: Bearer '
        tr -d '[:space:]' <"${TOKEN_FILE}"
        printf '\n'
    } >"${AUTH_HEADER}"
    AUTH_ARGS=(-H "@${AUTH_HEADER}")
    debug "Authenticated GitHub API request"
else
    debug "No token mounted: unauthenticated GitHub API request (60 per hour per IP)"
fi

# retry up to 5 times with 5 second delays for any error including HTTP 404 etc; on failure show why (rate limit, 404...)
curl --fail-with-body \
    --retry 5 \
    --retry-delay 5 \
    --retry-all-errors \
    -sSL \
    "${AUTH_ARGS[@]}" \
    "${API}" \
    -o "${API_JSON}" || {
    rc=$?
    debug "GitHub API request failed (curl exit ${rc}): $(head -c 300 "${API_JSON}" 2>/dev/null | tr '\n' ' ')"
    exit "${rc}"
}

debug "GitHub API response downloaded"
debug "Filtering assets using jq"

TGZ_URLS=$(jq \
    -r \
    --arg arch_filter "${ARCH_FILTER}" \
    '.assets
     | sort_by(.size)
     | reverse
     | .[]
     | select(.name | test($arch_filter; "i"))
     | .browser_download_url' \
    "${API_JSON}")

if [[ -z "${TGZ_URLS}" ]]; then
    debug "No assets matched filter '${ARCH_FILTER}'"
    exit 3
fi

debug "Matched asset URLs:"
debug "${TGZ_URLS}"

for URL in ${TGZ_URLS}; do
    debug "Selected URL=${URL}"
    # WARNING: in case of multiple matches, this only prints the first matched asset
    echo "${URL}"
    break
done
