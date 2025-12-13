#!/usr/bin/env bash
set -euo pipefail

HOST_NAME=homeserver
hostnamectl hostname $HOST_NAME
