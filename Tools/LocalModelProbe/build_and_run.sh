#!/bin/zsh

set -euo pipefail

tool_dir="${0:A:h}"
model_dir="${1:-${tool_dir:h:h}/PrivateModelAssets/Qwen3-4B-Instruct-2507-4bit}"
prompt="${2:-我今天有点累，你能陪陪我吗？}"

cd "$tool_dir"
"$tool_dir/build_runtime.sh"
release_dir="$tool_dir/.build/arm64-apple-macosx/release"
exec "$release_dir/notchflow-model-probe" "$model_dir" "$prompt"
