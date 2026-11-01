#!/usr/bin/env bash
# shellcheck shell=bash
# Shared helpers for the release-binary install scripts (sourced, not executed).

CACHE_DIR="${CACHE_DIR:-/runner/cache}"

log() {
    echo "=== $* ==="
}

debug() {
    echo "[DEBUG] $*" >&2
}

tmp_name() {
    # Usage: tmp_name <name> <version> <ext>
    # Normalizes version to be filesystem-safe.
    local name="$1"
    local version="$2"
    local ext="$3"
    local safe_version="${version//\//-}"
    safe_version="${safe_version// /_}"
    echo "${CACHE_DIR}/${name}-${safe_version}.${ext}"
}

fetch() {
    # Usage: fetch <dest> <url>
    curl -fsSL --retry 5 --retry-delay 5 --retry-all-errors -o "$1.part" "$2" && mv "$1.part" "$1"
}

download_if_missing() {
    # Usage: download_if_missing <dest> <url>
    local dest="$1"
    local url="$2"

    if [[ -f "$dest" ]]; then
        debug "Using cached $dest"
        return 0
    fi

    fetch "$dest" "$url"
}

download_if_missing_cmd() {
    # Usage: download_if_missing_cmd <dest> <command...>
    # Runs the command ONLY if <dest> is missing, and expects the command to print the URL.
    local dest="$1"
    shift

    if [[ -f "$dest" ]]; then
        debug "Using cached $dest"
        return 0
    fi

    local url
    url="$("$@")"
    fetch "$dest" "$url"
}

verify() {
    # Usage: verify <file> <asset-name-in-checksum-file> <checksum-file>
    # Checksum lines look like "<sha256>  <name>" or "<sha256> *<name>".
    local want
    want="$(awk -v n="$2" '{f=$2; sub(/^\*/, "", f); if (f == n) {print $1; exit}}' "$3")"
    [[ -n "$want" ]] || {
        echo "No checksum for $2 in $3" >&2
        return 1
    }
    echo "${want}  $1" | sha256sum -c -
}
