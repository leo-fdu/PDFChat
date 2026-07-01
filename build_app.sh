#!/bin/zsh
# 组装 PDFChat.app bundle
set -e
cd "$(dirname "$0")"

echo "==> swift build -c release"
swift build -c release

BUILD=.build/release
APP=PDFChat.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp "$BUILD/PDFChat" "$APP/Contents/MacOS/PDFChat"
cp Info.plist "$APP/Contents/Info.plist"
printf "APPLPDFC" > "$APP/Contents/PkgInfo"

chmod +x "$APP/Contents/MacOS/PDFChat"

echo "==> done: $APP"
echo "双击运行或拖入 /Applications；在 Finder「显示简介 → 打开方式 → 全部更改」可设为默认 PDF 打开方式。"