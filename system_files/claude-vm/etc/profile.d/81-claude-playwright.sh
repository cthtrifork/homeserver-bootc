# shellcheck shell=sh
# Playwright is installed globally under /usr (library only); the browser is Fedora's chromium RPM.
export NODE_PATH="/usr/lib/node_modules${NODE_PATH:+:$NODE_PATH}"
export PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1
export PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH=/usr/bin/chromium-browser
