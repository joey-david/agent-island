#!/bin/bash
# Builds build/Topnotchers.app and build/topnotchers-hook.
set -euo pipefail
cd "$(dirname "$0")"
APP="build/Topnotchers.app"
FLAGS=(-O -swift-version 5 -target arm64-apple-macos14.0)
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/Info.plist "$APP/Contents/"
swiftc "${FLAGS[@]}" Sources/App/*.swift -o "$APP/Contents/MacOS/Topnotchers"
swiftc "${FLAGS[@]}" Sources/Hook/main.swift -o build/topnotchers-hook
codesign --force -s - build/topnotchers-hook
codesign --force -s - "$APP"
