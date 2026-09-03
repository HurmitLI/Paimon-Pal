#!/bin/zsh

set -euo pipefail

tool_dir="${0:A:h}"
metal_source_dir="$tool_dir/.build/checkouts/mlx-swift/Source/Cmlx/mlx-generated/metal"
release_dir="$tool_dir/.build/arm64-apple-macosx/release"

cd "$tool_dir"
swift build -c release --arch arm64

air_files=()
for source in "$metal_source_dir"/*.metal; do
    name="${source:t:r}"
    air_file="$release_dir/$name.air"
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
        -o "$air_file"
    air_files+=("$air_file")
done

xcrun -sdk macosx metallib "${air_files[@]}" -o "$release_dir/mlx.metallib"
test -x "$release_dir/notchflow-model-probe"
test -s "$release_dir/mlx.metallib"
