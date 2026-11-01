#!/usr/bin/env bash
set -euo pipefail

# Root-only age key. Users get their own 0600 copy via tmpfiles.d
# (13-caspertdk-sops.conf); nothing is exported into login shells.
install -D -m 0600 -o root -g root /run/secrets/agekey /usr/lib/sops/age/keys.txt
