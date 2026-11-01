#!/usr/bin/env bash
set -euo pipefail

SOPS_AGE_KEY="$(cat /run/secrets/agekey)"
install -D -m 0600 -o root -g root /run/secrets/agekey /usr/lib/sops/age/keys.txt
# root-only: contains the age secret key
install -m 0600 -o root -g root /dev/null /etc/profile.d/61-age-sops-private.sh
printf "export SOPS_AGE_KEY=%s\n" "$SOPS_AGE_KEY" >/etc/profile.d/61-age-sops-private.sh
