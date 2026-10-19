#!/bin/bash
# Builds build/Agent Island.app and build/island-hook.
set -euo pipefail
cd "$(dirname "$0")"
APP="build/Agent Island.app"
FLAGS=(-O -swift-version 5 -target arm64-apple-macos14.0)
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/Info.plist "$APP/Contents/"
swiftc "${FLAGS[@]}" Sources/App/*.swift -o "$APP/Contents/MacOS/AgentIsland"
swiftc "${FLAGS[@]}" Sources/Hook/main.swift -o build/island-hook
codesign --force -s - build/island-hook
codesign --force -s - "$APP"
