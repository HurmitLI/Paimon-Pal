#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA_PATH="$PROJECT_ROOT/build/NotchFlowDerivedData"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/Debug/NotchFlow.app"
ENTITLEMENTS_PATH="$PROJECT_ROOT/NotchFlow/Resources/NotchFlow.entitlements"

cd "$PROJECT_ROOT"

echo "[1/5] 编译 Paimon Pal…"
/usr/bin/xcodebuild \
  -quiet \
  -project NotchFlow.xcodeproj \
  -scheme NotchFlow \
  -configuration Debug \
  -destination "platform=macOS,arch=arm64" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  build

echo "[2/5] 内置 Paimon Pal 本地 TTS…"
"$PROJECT_ROOT/scripts/embed_paimon_tts_runtime.sh" "$APP_PATH"

echo "[3/5] 添加本机验证签名…"
/usr/bin/codesign --force --deep --sign - --entitlements "$ENTITLEMENTS_PATH" "$APP_PATH"

echo "[4/5] 关闭其他 Paimon Pal/NotchFlow 实例…"
if RUNNING_PIDS="$(/usr/bin/pgrep -x NotchFlow 2>/dev/null)"; then
  while IFS= read -r RUNNING_PID; do
    [[ -n "$RUNNING_PID" ]] && /bin/kill "$RUNNING_PID"
  done <<< "$RUNNING_PIDS"

  for _ in {1..30}; do
    /usr/bin/pgrep -x NotchFlow >/dev/null 2>&1 || break
    /bin/sleep 0.1
  done
fi

if /usr/bin/pgrep -x NotchFlow >/dev/null 2>&1; then
  echo "无法关闭旧的 NotchFlow 实例，请先手动退出后重试。" >&2
  exit 1
fi

echo "[5/5] 启动 Paimon Pal…"
/usr/bin/open "$APP_PATH"

echo "已启动：$APP_PATH"
