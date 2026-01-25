#!/usr/bin/bash

set -euo pipefail

trap '[[ $BASH_COMMAND != echo* ]] && [[ $BASH_COMMAND != log* ]] && echo "+ $BASH_COMMAND"' DEBUG

log() {
  echo "=== $* ==="
}

export SOPS_AGE_KEY_FILE="/usr/lib/sops/age/keys.txt"

if [[ ! -f "$SOPS_AGE_KEY_FILE" ]]; then
  echo "Error: SOPS_AGE_KEY_FILE ($SOPS_AGE_KEY_FILE) does not exist" >&2
  exit 1
fi

grep -q '^AGE-SECRET-KEY-1' /usr/lib/sops/age/keys.txt || { echo "Not an age key file"; exit 1; }

log "Decrypting SSH key"
sops --decrypt --input-type binary --output-type binary --output /usr/share/secrets/ssh/id_ed25519 /usr/share/secrets/ssh/id_ed25519.enc
chmod 600 /usr/share/secrets/ssh/id_ed25519
