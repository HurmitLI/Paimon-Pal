#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA_PATH="$PROJECT_ROOT/build/PaimonPalLocalDMGData"
INTERNAL_APP_PATH="$DERIVED_DATA_PATH/Build/Products/Release/NotchFlow.app"
ENTITLEMENTS_PATH="$PROJECT_ROOT/NotchFlow/Resources/NotchFlow.entitlements"
INFO_PLIST_PATH="$PROJECT_ROOT/NotchFlow/Resources/Info.plist"
OUTPUT_DIR="$PROJECT_ROOT/dist"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST_PATH")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST_PATH")"
DMG_PATH="$OUTPUT_DIR/Paimon-Pal-${VERSION}-${BUILD}-arm64-local.dmg"

/bin/mkdir -p "$OUTPUT_DIR"
if [[ -e "$DMG_PATH" ]]; then
    DMG_PATH="$OUTPUT_DIR/Paimon-Pal-${VERSION}-${BUILD}-arm64-local-$(/bin/date +%Y%m%d-%H%M%S).dmg"
fi

STAGING_DIR="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/PaimonPal-DMG.XXXXXX")"
cleanup() {
    if [[ -n "${STAGING_DIR:-}" && "$STAGING_DIR" == *"/PaimonPal-DMG."* ]]; then
        /bin/rm -rf "$STAGING_DIR"
    fi
}
trap cleanup EXIT

cd "$PROJECT_ROOT"

echo "[1/6] 构建 Paimon Pal ${VERSION} (${BUILD}) Release arm64…"
/usr/bin/xcodebuild \
    -quiet \
    -project NotchFlow.xcodeproj \
    -scheme NotchFlow \
    -configuration Release \
    -destination "platform=macOS,arch=arm64" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    CODE_SIGNING_ALLOWED=NO \
    build

echo "[2/6] 内置 Paimon Pal 本地 TTS…"
"$PROJECT_ROOT/scripts/embed_paimon_tts_runtime.sh" "$INTERNAL_APP_PATH"

echo "[3/6] 添加仅供本机测试的临时签名…"
/usr/bin/codesign \
    --force \
    --deep \
    --sign - \
    --entitlements "$ENTITLEMENTS_PATH" \
    "$INTERNAL_APP_PATH"
/usr/bin/codesign --verify --deep --strict "$INTERNAL_APP_PATH"

echo "[4/6] 准备 Paimon Pal 安装盘内容…"
/usr/bin/ditto "$INTERNAL_APP_PATH" "$STAGING_DIR/Paimon Pal.app"
/bin/ln -s /Applications "$STAGING_DIR/Applications"

echo "[5/6] 生成并验证 DMG…"
/usr/bin/hdiutil create \
    -volname "Paimon Pal ${VERSION}" \
    -srcfolder "$STAGING_DIR" \
    -format UDZO \
    -fs HFS+ \
    "$DMG_PATH"
/usr/bin/hdiutil verify "$DMG_PATH"

echo "[6/6] 计算校验值…"
CHECKSUM="$(/usr/bin/shasum -a 256 "$DMG_PATH" | /usr/bin/awk '{print $1}')"

echo ""
echo "Paimon Pal 本机测试 DMG 已生成："
echo "$DMG_PATH"
echo "SHA-256: $CHECKSUM"
echo "注意：这是临时签名包，未经过 Developer ID 正式签名和苹果公证。"
