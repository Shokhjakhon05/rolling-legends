#!/usr/bin/env bash
# Puts the Poing Studios AdMob plugin (pinned version) into addons/admob. The plugin is not
# kept in this repository; CI and a fresh checkout run this once.
set -euo pipefail
PLUGIN_VERSION="v5.1.0"
GODOT_VERSION="${GODOT_VERSION:-4.6.3}"
cd "$(dirname "$0")/.."
BASE="https://github.com/poingstudios/godot-admob-plugin/releases/download/${PLUGIN_VERSION}"
TMP="$(mktemp -d)"
curl -4 -sSL --retry 3 -o "$TMP/plugin.zip" "$BASE/poing-godot-admob-${PLUGIN_VERSION}.zip"
curl -4 -sSL --retry 3 -o "$TMP/android.zip" "$BASE/android-template-v${GODOT_VERSION}.zip"
unzip -q -o "$TMP/plugin.zip" -d "$TMP/plugin"
unzip -q -o "$TMP/android.zip" -d "$TMP/android"
rm -rf addons/admob
mkdir -p addons
cp -r "$TMP/plugin/poing-godot-admob/addons/admob" addons/admob
# The plugin's samples, C# and iOS parts are left in place (its editor code refers to them)
# and kept out of the game by the export filter in export_presets.cfg.
mkdir -p addons/admob/android/bin
cp "$TMP/android/package.gd" addons/admob/android/bin/ 2>/dev/null || true
cp -r "$TMP/android/ads" addons/admob/android/bin/ads   # no mediation networks
rm -rf "$TMP"
echo "AdMob plugin ${PLUGIN_VERSION} for Godot ${GODOT_VERSION} is in addons/admob"
