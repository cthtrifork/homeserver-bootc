#!/usr/bin/env bash

# Your persistent public URL is: portableinfo.a.pinggy.link
# Your persistent TCP port is: 21412

if [ -n "$PINGGY_TOKEN" ]; then
    USER="${PINGGY_TOKEN}+tcp@${PINGGY_HOST}"
else
    USER="tcp@${PINGGY_HOST}"
fi

ssh -p 443 \
    -o StrictHostKeyChecking=no \
    -o ServerAliveInterval=30 \
    -R0:localhost:22 \
    "$USER"
