# shellcheck shell=sh
# Playwright is installed globally under /usr (library only); the browser is Fedora's chromium RPM.
export NODE_PATH="/usr/lib/node_modules${NODE_PATH:+:$NODE_PATH}"
export PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1
export PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH=/usr/bin/chromium-browser
# Playwright's bundled ffmpeg (recordVideo -> .webm) is baked into the image here; there is no browser in this directory.
export PLAYWRIGHT_BROWSERS_PATH=/usr/share/claude-vm/ms-playwright
