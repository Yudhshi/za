#!/bin/bash
# Nippo.app を dist/ に組み立てる(CLT のみ・Xcode 不要)
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP="dist/Nippo.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/NippoApp "$APP/Contents/MacOS/Nippo"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# ad-hoc 署名。TCC 許可はバンドルIDに紐づくため再ビルド後も概ね保持されるが、
# 権限ダイアログが再出現したら再許可すること。
codesign --force -s - "$APP"

echo "Built: $APP"
