#!/usr/bin/env bash
# Install the tagged dev build as ~/Applications/HyprMux.app, so the Dock,
# Cmd+Tab and Finder show "HyprMux" (macOS labels an app by its folder name).
# usage: scripts/hypermux-install.sh [tag]   (default: agentic)
set -euo pipefail
tag=${1:-agentic}
src="$HOME/Library/Developer/Xcode/DerivedData/cmux-$tag/Build/Products/Debug/cmux DEV $tag.app"
dst="$HOME/Applications/HyprMux.app"
[ -d "$src" ] || { echo "no build at $src -- run: ./scripts/reload.sh --tag $tag" >&2; exit 1; }
pkill -f "cmux DEV $tag.app/Contents/MacOS" 2>/dev/null || true
pkill -f "HyprMux.app/Contents/MacOS" 2>/dev/null || true
sleep 1
mkdir -p "$HOME/Applications"
rm -rf "$dst"
ditto "$src" "$dst"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$dst"
echo "installed $dst"
