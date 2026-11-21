#!/bin/sh
# 在 macOS 上构建未签名 IPA（TrollStore / 自签工具可直接使用）。
set -e
cd "$(dirname "$0")/.."

xcodebuild \
  -project DSHClient.xcodeproj \
  -scheme DSHClient \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  build

APP="build/Build/Products/Release-iphoneos/DSHClient.app"
if [ ! -d "$APP" ]; then
  echo "构建失败：找不到 $APP" >&2
  exit 1
fi

rm -rf Payload DSHClient.ipa
mkdir Payload
cp -R "$APP" Payload/
zip -qry DSHClient.ipa Payload

echo ""
echo "IPA 已生成：$(pwd)/DSHClient.ipa"
