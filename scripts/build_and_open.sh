#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA_PATH="$PROJECT_ROOT/build/DerivedData"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/Debug/NotchFlowFeasibilityLab.app"
ENTITLEMENTS_PATH="$PROJECT_ROOT/NotchFlowFeasibilityLab/Resources/NotchFlowFeasibilityLab.entitlements"

cd "$PROJECT_ROOT"

echo "[1/3] 编译 NotchFlow 第一阶段实验 App…"
/usr/bin/xcodebuild \
  -quiet \
  -project NotchFlowFeasibilityLab.xcodeproj \
  -scheme NotchFlowFeasibilityLab \
  -configuration Debug \
  -destination "platform=macOS,arch=arm64" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  build

echo "[2/3] 添加仅供本机验证使用的临时签名…"
/usr/bin/codesign \
  --force \
  --deep \
  --sign - \
  --entitlements "$ENTITLEMENTS_PATH" \
  "$APP_PATH"

echo "[3/3] 启动实验 App…"
/usr/bin/open "$APP_PATH"

echo "已启动：$APP_PATH"

