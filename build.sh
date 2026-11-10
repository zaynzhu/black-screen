#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="BlackScreen"
BUILD_DIR="build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"

echo "编译 $APP_NAME ..."
swiftc -O Sources/main.swift -o "$BINARY" -framework Cocoa

cp Resources/Info.plist "$APP_BUNDLE/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

# 本地运行用 ad-hoc 签名即可
codesign --force --sign - "$APP_BUNDLE" >/dev/null 2>&1 || true

echo "构建完成: $APP_BUNDLE"
echo "运行: open \"$APP_BUNDLE\""
