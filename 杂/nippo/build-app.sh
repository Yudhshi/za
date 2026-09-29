#!/bin/bash
# Yudh.app(旧 Nippo.app)を dist/ に組み立てる(CLT のみ・Xcode 不要)
#   英語タブの素材を取り込むときは IELTS アプリのフォルダを渡す(一度取り込めば次回からは不要):
#   IELTS_DIR=~/Downloads/ielts-dist-v71 ./build-app.sh
set -euo pipefail
cd "$(dirname "$0")"

if [ -n "${IELTS_DIR:-}" ]; then
    node scripts/import-english.mjs "$IELTS_DIR"
fi

swift build -c release --product NippoApp

APP="dist/Yudh.app"
# 旧名で動いているものを終了し、旧名のアプリも片付ける(同じバンドル ID が 2 つ並ばないように)
pkill -x Yudh 2>/dev/null || true
pkill -x Nippo 2>/dev/null || true
rm -rf "$APP" "dist/Nippo.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/NippoApp "$APP/Contents/MacOS/Yudh"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# アイコンの元絵は Resources/AppIcon/AppIcon.svg(描き直したら node scripts/make-icon.mjs で icns を作り直す)
cp Resources/AppIcon/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# 英語タブの素材(scripts/import-english.mjs で作る。教材由来なのでリポジトリには入れていない)
if [ -d Resources/English ]; then
    cp -R Resources/English "$APP/Contents/Resources/English"
else
    echo "注意: Resources/English がありません。英語タブを使うには IELTS_DIR=<IELTS アプリのフォルダ> を付けて実行"
fi

# ad-hoc 署名。TCC 許可はバンドルIDに紐づくため再ビルド後も概ね保持されるが、
# 権限ダイアログが再出現したら再許可すること。
codesign --force -s - "$APP"
# Finder・Dock のアイコンのキャッシュを更新
touch "$APP"

echo "Built: $APP"
# そのまま起動(NO_OPEN=1 で抑止)
[ -n "${NO_OPEN:-}" ] || open "$APP"
