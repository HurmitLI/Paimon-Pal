#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA_PATH="$PROJECT_ROOT/build/NotchFlowDerivedData"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/Debug/NotchFlow.app"
ENTITLEMENTS_PATH="$PROJECT_ROOT/NotchFlow/Resources/NotchFlow.entitlements"

cd "$PROJECT_ROOT"

echo "[1/3] 编译 NotchFlow 交互底座…"
/usr/bin/xcodebuild \
  -quiet \
  -project NotchFlow.xcodeproj \
  -scheme NotchFlow \
  -configuration Debug \
  -destination "platform=macOS,arch=arm64" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  build

echo "[2/3] 添加本机验证签名…"
/usr/bin/codesign --force --deep --sign - --entitlements "$ENTITLEMENTS_PATH" "$APP_PATH"

echo "[3/3] 启动 NotchFlow…"
/usr/bin/open "$APP_PATH"

echo "已启动：$APP_PATH"
