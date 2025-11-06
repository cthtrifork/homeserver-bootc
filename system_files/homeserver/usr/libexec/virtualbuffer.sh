#!/bin/bash
echo "Initializing a virtual frame buffer"
Xvfb :99 -screen 0 1024x768x24 > /dev/null 2>&1 &
