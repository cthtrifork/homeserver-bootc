#!/usr/bin/env bash
set -euo pipefail

# Give the user a writable copy of trivy-scanner so its in-app updater works. The packaged
# binary in /usr/bin is read-only (bootc), so the updater cannot replace it; a copy in
# ~/.local/bin can be replaced. The image ships a seed at /usr/share/trivy-scanner.
#
# This runs on every boot, so it must not undo a self-update (unlike the dotfiles rsync):
#   - no user copy yet                      -> seed it
#   - user copy is still the one we seeded  -> refresh it when the image has a newer seed
#   - user copy differs (self-updated)      -> leave it alone
# To go back to the image's version, delete ~/.local/bin/trivy-scanner and run this again.

seed_dir="${TRIVY_SCANNER_SEED_DIR:-/usr/share/trivy-scanner}"
bin_dir="$HOME/.local/bin"
state_dir="$HOME/.local/share/trivy-scanner"
app_dir="$HOME/.local/share/applications"
desktop_id="io.github.cthtrifork.trivy-scanner.desktop"
system_desktop="${TRIVY_SCANNER_SYSTEM_DESKTOP:-/usr/share/applications/$desktop_id}"

[ -f "$seed_dir/trivy-scanner" ] || exit 0

mkdir -p "$bin_dir" "$state_dir" "$app_dir"
seed_sha="$(sha256sum "$seed_dir/trivy-scanner" | cut -d' ' -f1)"
target="$bin_dir/trivy-scanner"
seeded_file="$state_dir/seeded-sha256"

install_seed() {
    # Copy then rename, so a running instance keeps its old inode and a crash leaves no half file.
    install -m 0755 "$seed_dir/trivy-scanner" "$target.new"
    mv -f "$target.new" "$target"
    echo "$seed_sha" >"$seeded_file"
}

if [ ! -f "$target" ]; then
    install_seed
    echo "Seeded $target"
elif [ -f "$seeded_file" ] && [ "$(sha256sum "$target" | cut -d' ' -f1)" = "$(cat "$seeded_file")" ]; then
    if [ "$seed_sha" != "$(cat "$seeded_file")" ]; then
        install_seed
        echo "Refreshed $target from the image"
    fi
else
    echo "Keeping $target: it is not the copy this image seeded (self-updated?)"
fi

# Launcher for the user copy. A file of the same name in ~/.local/share/applications takes
# precedence over the one the RPM installs, so the menu entry starts the updatable copy.
if [ -f "$system_desktop" ]; then
    sed "s|^Exec=.*|Exec=$target|" "$system_desktop" >"$app_dir/$desktop_id"
fi
