#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_ROOT="$PROJECT_ROOT/build/PetAnimationLab"
APP_PATH="$BUILD_ROOT/PetAnimationLab.app"
CONTENTS_PATH="$APP_PATH/Contents"
EXECUTABLE_PATH="$CONTENTS_PATH/MacOS/PetAnimationLab"

if /usr/bin/pgrep -x PetAnimationLab >/dev/null 2>&1; then
  /usr/bin/pkill -x PetAnimationLab
  /bin/sleep 0.2
fi

mkdir -p "$CONTENTS_PATH/MacOS" "$CONTENTS_PATH/Resources"

echo "[1/4] 编译独立宠物动画播放器…"
/usr/bin/xcrun swiftc \
  -parse-as-library \
  -target arm64-apple-macos14.0 \
  -framework AppKit \
  -framework SwiftUI \
  -framework ImageIO \
  "$PROJECT_ROOT"/PetAnimationLab/*.swift \
  -o "$EXECUTABLE_PATH"

echo "[2/4] 写入 App 信息…"
/bin/cp "$PROJECT_ROOT/PetAnimationLab/Info.plist" "$CONTENTS_PATH/Info.plist"

echo "[3/4] 添加本机临时签名…"
/usr/bin/codesign --force --deep --sign - "$APP_PATH"

echo "[4/4] 启动播放器…"
/usr/bin/open "$APP_PATH"

echo "已启动：$APP_PATH"
