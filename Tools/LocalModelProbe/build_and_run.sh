#!/bin/zsh

set -euo pipefail

tool_dir="${0:A:h}"
model_dir="${1:-${tool_dir:h:h}/PrivateModelAssets/Qwen3-4B-Instruct-2507-4bit}"
prompt="${2:-我今天有点累，你能陪陪我吗？}"

cd "$tool_dir"
swift build -c release

metal_source_dir="$tool_dir/.build/checkouts/mlx-swift/Source/Cmlx/mlx-generated/metal"
release_dir="$tool_dir/.build/arm64-apple-macosx/release"

for source in "$metal_source_dir"/*.metal; do
    name="${source:t:r}"
    xcrun -sdk macosx metal \
        -x metal \
        -Wall \
        -Wextra \
        -fno-fast-math \
        -Wno-c++17-extensions \
        -Wno-c++20-extensions \
        -mmacosx-version-min=14.0 \
        -c "$source" \
        -I"$metal_source_dir" \
        -o "$release_dir/$name.air"
done

xcrun -sdk macosx metallib "$release_dir"/*.air -o "$release_dir/mlx.metallib"
exec "$release_dir/notchflow-model-probe" "$model_dir" "$prompt"
