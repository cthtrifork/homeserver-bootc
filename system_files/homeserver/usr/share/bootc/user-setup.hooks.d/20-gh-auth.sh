#!/usr/bin/env bash
# Authenticate the GitHub CLI from the 0600 token file instead of an exported GITHUB_TOKEN.
token_file="${HOME}/.config/github-token"
if [ -r "$token_file" ] && command -v gh >/dev/null; then
    gh auth login --hostname github.com --with-token <"$token_file" || true
fi
