#!/usr/bin/env bash
set -euo pipefail

# checks if any regular home areas exist. 
# If none are found, it searches for service credentials starting with `home.create.` to create users at boot. 
homectl firstboot