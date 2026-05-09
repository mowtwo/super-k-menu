#!/usr/bin/env bash
set -euo pipefail

APP_PATH="/Applications/SuperKMenu.app"
EXTENSION_ID="com.chenwencheng.SuperKMenu.FinderExtension"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "Stopping SuperKMenu..."
killall SuperKMenu 2>/dev/null || true

echo "Disabling Finder extension..."
pluginkit -e ignore -i "$EXTENSION_ID" 2>/dev/null || true

echo "Unregistering known Finder extension copies..."
pluginkit -r "$APP_PATH/Contents/PlugIns/SuperKMenuFinderExtension.appex" 2>/dev/null || true
pluginkit -r "$REPO_ROOT/build/Release/SuperKMenu.app/Contents/PlugIns/SuperKMenuFinderExtension.appex" 2>/dev/null || true
pluginkit -r "$REPO_ROOT/dist/SuperKMenu.app/Contents/PlugIns/SuperKMenuFinderExtension.appex" 2>/dev/null || true

echo "Removing installed app..."
rm -rf "$APP_PATH"

echo "Removing local configuration and logs..."
rm -rf "$HOME/.super-k-menu"
rm -rf "$HOME/Library/Containers/com.chenwencheng.SuperKMenu.FinderExtension/Data/Library/Application Support/SuperKMenu"
rm -f /tmp/superkmenu-main.log

echo "Restarting Finder..."
killall Finder 2>/dev/null || true

echo "Clean local SuperKMenu state is ready."
