#!/bin/zsh
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "用法：$0 /path/to/Paimon.app" >&2
  exit 64
fi

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="$1"
RESOURCE_ROOT="$APP_PATH/Contents/Resources/PaimonTTS"
MODEL_SOURCE="$PROJECT_ROOT/PrivateTTSAssets/Qwen3-TTS-12Hz-1.7B-VoiceDesign-4bit"
SITE_PACKAGES_SOURCE="$PROJECT_ROOT/.tts-lab-venv/lib/python3.12/site-packages"
PYTHON_LINK="$PROJECT_ROOT/.tts-lab-venv/bin/python"
RUNTIME_SCRIPT_SOURCE="$PROJECT_ROOT/Tools/TTSVoiceLab/paimon_tts_runtime.py"
VOICE_REFERENCE_SOURCE="$PROJECT_ROOT/PrivateTTSAssets/voice-candidates-characterful/P1-清脆反应感版.wav"

if [[ ! -d "$APP_PATH/Contents/Resources" ]]; then
  echo "App Resources 不存在：$APP_PATH" >&2
  exit 66
fi
for REQUIRED_PATH in "$MODEL_SOURCE" "$SITE_PACKAGES_SOURCE" "$PYTHON_LINK" "$RUNTIME_SCRIPT_SOURCE" "$VOICE_REFERENCE_SOURCE"; do
  if [[ ! -e "$REQUIRED_PATH" ]]; then
    echo "缺少本地 TTS 资源：$REQUIRED_PATH" >&2
    exit 66
  fi
done

PYTHON_EXECUTABLE="$(/usr/bin/readlink "$PYTHON_LINK")"
if [[ "$PYTHON_EXECUTABLE" != /* || ! -x "$PYTHON_EXECUTABLE" ]]; then
  echo "无法解析独立 Python：$PYTHON_LINK" >&2
  exit 66
fi
PYTHON_ROOT="$(cd "$(dirname "$PYTHON_EXECUTABLE")/.." && pwd)"

echo "  · 内置 Python 3.12 运行时"
/bin/mkdir -p "$RESOURCE_ROOT/Runtime/Python"
/bin/cp -cR "$PYTHON_ROOT/." "$RESOURCE_ROOT/Runtime/Python/"

echo "  · 内置 MLX Audio 依赖"
/bin/mkdir -p "$RESOURCE_ROOT/Runtime/SitePackages"
/bin/cp -cR "$SITE_PACKAGES_SOURCE/." "$RESOURCE_ROOT/Runtime/SitePackages/"

echo "  · 内置 P1 固定声纹、生成脚本和 TTS 模型"
/bin/cp "$RUNTIME_SCRIPT_SOURCE" "$RESOURCE_ROOT/Runtime/paimon_tts_runtime.py"
/bin/chmod 755 "$RESOURCE_ROOT/Runtime/paimon_tts_runtime.py"
/bin/cp "$VOICE_REFERENCE_SOURCE" "$RESOURCE_ROOT/VoiceReference.wav"
/bin/mkdir -p "$RESOURCE_ROOT/Model"
/bin/cp -cR "$MODEL_SOURCE/." "$RESOURCE_ROOT/Model/"

PYTHON_HOME="$RESOURCE_ROOT/Runtime/Python"
PYTHON_PATH="$RESOURCE_ROOT/Runtime/SitePackages"
env \
  PYTHONHOME="$PYTHON_HOME" \
  PYTHONPATH="$PYTHON_PATH" \
  PYTHONDONTWRITEBYTECODE=1 \
  HF_HUB_OFFLINE=1 \
  TRANSFORMERS_OFFLINE=1 \
  "$PYTHON_HOME/bin/python3.12" - <<'PY'
import mlx.core
import mlx_audio
import numpy
from mlx_audio.tts.utils import load_model
print("Paimon TTS bundled Python preflight passed")
PY

echo "  · TTS 资源大小：$(/usr/bin/du -sh "$RESOURCE_ROOT" | /usr/bin/awk '{print $1}')"
