#!/usr/bin/env python3
"""Convert one chroma-key 4xN pet sheet into a stable transparent sheet.

This is deterministic post-processing only. It does not invent or interpolate
frames. Each generated cell keeps its original pixels while the background is
removed and the character anchor is registered to the median cell anchor.
"""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
from statistics import median

from PIL import Image


def parse_color(value: str) -> tuple[int, int, int]:
    value = value.removeprefix("#")
    if len(value) != 6:
        raise argparse.ArgumentTypeError("color must use #RRGGBB")
    try:
        return tuple(int(value[index : index + 2], 16) for index in (0, 2, 4))
    except ValueError as error:
        raise argparse.ArgumentTypeError("color must use #RRGGBB") from error


def crop_boxes(width: int, height: int, columns: int, rows: int) -> list[tuple[int, int, int, int]]:
    boxes: list[tuple[int, int, int, int]] = []
    for index in range(columns * rows):
        column = index % columns
        row = index // columns
        left = round(column * width / columns)
        right = round((column + 1) * width / columns)
        top = round(row * height / rows)
        bottom = round((row + 1) * height / rows)
        boxes.append((left, top, right, bottom))
    return boxes


def remove_chroma(
    image: Image.Image,
    key: tuple[int, int, int],
    inner: float,
    outer: float,
) -> Image.Image:
    if not 0 <= inner < outer:
        raise ValueError("expected 0 <= inner < outer")

    source = image.convert("RGBA")
    output: list[tuple[int, int, int, int]] = []
    for red, green, blue, source_alpha in source.getdata():
        distance = math.dist((red, green, blue), key)
        if source_alpha == 0 or distance <= inner:
            output.append((0, 0, 0, 0))
            continue
        if distance >= outer:
            output.append((red, green, blue, source_alpha))
            continue

        coverage = (distance - inner) / (outer - inner)
        alpha = max(1, min(255, round(source_alpha * coverage)))
        normalized = alpha / 255
        recovered = tuple(
            max(0, min(255, round((observed - key_channel * (1 - normalized)) / normalized)))
            for observed, key_channel in zip((red, green, blue), key)
        )
        output.append((*recovered, alpha))

    result = Image.new("RGBA", source.size)
    result.putdata(output)
    return result


def alpha_bounds(image: Image.Image, threshold: int = 16) -> tuple[int, int, int, int] | None:
    alpha = image.getchannel("A")
    mask = alpha.point(lambda value: 255 if value > threshold else 0)
    return mask.getbbox()


def connected_components(
    image: Image.Image,
    threshold: int = 16,
    minimum_pixels: int = 500,
) -> list[tuple[int, tuple[int, int, int, int]]]:
    alpha = image.getchannel("A")
    width, height = image.size
    pixels = alpha.load()
    visited = bytearray(width * height)
    components: list[tuple[int, tuple[int, int, int, int]]] = []

    for y in range(height):
        for x in range(width):
            start = y * width + x
            if visited[start] or pixels[x, y] <= threshold:
                continue

            stack = [(x, y)]
            visited[start] = 1
            count = 0
            minimum_x = maximum_x = x
            minimum_y = maximum_y = y
            while stack:
                current_x, current_y = stack.pop()
                count += 1
                minimum_x = min(minimum_x, current_x)
                maximum_x = max(maximum_x, current_x)
                minimum_y = min(minimum_y, current_y)
                maximum_y = max(maximum_y, current_y)
                for next_x, next_y in (
                    (current_x - 1, current_y),
                    (current_x + 1, current_y),
                    (current_x, current_y - 1),
                    (current_x, current_y + 1),
                ):
                    if not (0 <= next_x < width and 0 <= next_y < height):
                        continue
                    index = next_y * width + next_x
                    if visited[index] or pixels[next_x, next_y] <= threshold:
                        continue
                    visited[index] = 1
                    stack.append((next_x, next_y))

            if count >= minimum_pixels:
                components.append(
                    (count, (minimum_x, minimum_y, maximum_x + 1, maximum_y + 1))
                )
    return components


def order_components(
    components: list[tuple[int, tuple[int, int, int, int]]],
    columns: int,
    rows: int,
) -> list[tuple[int, int, int, int]]:
    expected = columns * rows
    if len(components) != expected:
        raise SystemExit(
            f"expected {expected} complete sprite components, found {len(components)}"
        )

    by_vertical_position = sorted(
        (bounds for _, bounds in components),
        key=lambda bounds: ((bounds[1] + bounds[3]) / 2, (bounds[0] + bounds[2]) / 2),
    )
    ordered: list[tuple[int, int, int, int]] = []
    for row in range(rows):
        row_bounds = by_vertical_position[row * columns : (row + 1) * columns]
        ordered.extend(sorted(row_bounds, key=lambda bounds: (bounds[0] + bounds[2]) / 2))
    return ordered


def translate(image: Image.Image, dx: int, dy: int) -> Image.Image:
    output = Image.new("RGBA", image.size)
    output.alpha_composite(image, (dx, dy))
    return output


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--qa-json", type=Path, required=True)
    parser.add_argument("--columns", type=int, default=4)
    parser.add_argument("--rows", type=int, default=4)
    parser.add_argument("--chroma-key", type=parse_color, default=parse_color("#FF00FF"))
    parser.add_argument("--inner", type=float, default=72)
    parser.add_argument("--outer", type=float, default=168)
    parser.add_argument("--max-anchor-shift", type=int, default=18)
    parser.add_argument("--layout-method", choices=("components", "slots"), default="components")
    args = parser.parse_args()

    sheet = Image.open(args.input).convert("RGBA")
    cleaned = remove_chroma(sheet, args.chroma_key, args.inner, args.outer)
    boxes = crop_boxes(cleaned.width, cleaned.height, args.columns, args.rows)
    if args.layout_method == "components":
        component_bounds = order_components(
            connected_components(cleaned),
            args.columns,
            args.rows,
        )
        cell_width = boxes[0][2] - boxes[0][0]
        cell_height = boxes[0][3] - boxes[0][1]
        frames = []
        for bounds in component_bounds:
            sprite = cleaned.crop(bounds)
            frame = Image.new("RGBA", (cell_width, cell_height))
            target_x = round((cell_width - sprite.width) / 2)
            target_y = cell_height - sprite.height - 12
            if target_x < 2 or target_y < 2:
                raise SystemExit(
                    f"sprite {bounds} cannot fit the target cell with safe padding"
                )
            frame.alpha_composite(sprite, (target_x, target_y))
            frames.append(frame)
    else:
        frames = [cleaned.crop(box) for box in boxes]
    bounds = [alpha_bounds(frame) for frame in frames]
    if any(value is None for value in bounds):
        raise SystemExit("one or more sprite cells are empty after chroma removal")

    concrete_bounds = [value for value in bounds if value is not None]
    centers = [(left + right) / 2 for left, _, right, _ in concrete_bounds]
    bottoms = [bottom for _, _, _, bottom in concrete_bounds]
    target_center = median(centers)
    target_bottom = median(bottoms)

    aligned: list[Image.Image] = []
    shifts: list[dict[str, int]] = []
    for frame, (left, top, right, bottom) in zip(frames, concrete_bounds):
        dx = round(target_center - (left + right) / 2)
        dy = round(target_bottom - bottom)
        dx = max(-args.max_anchor_shift, min(args.max_anchor_shift, dx))
        dy = max(-args.max_anchor_shift, min(args.max_anchor_shift, dy))
        aligned.append(translate(frame, dx, dy))
        shifts.append({"x": dx, "y": dy})

    output_width = frames[0].width * args.columns
    output_height = frames[0].height * args.rows
    output = Image.new("RGBA", (output_width, output_height))
    for index, frame in enumerate(aligned):
        column = index % args.columns
        row = index // args.columns
        output.alpha_composite(frame, (column * frame.width, row * frame.height))

    args.output.parent.mkdir(parents=True, exist_ok=True)
    output.save(args.output)

    final_bounds = [alpha_bounds(frame) for frame in aligned]
    edge_pixels: list[int] = []
    for frame in aligned:
        alpha = frame.getchannel("A")
        width, height = frame.size
        edge = (
            list(alpha.crop((0, 0, width, 2)).getdata())
            + list(alpha.crop((0, height - 2, width, height)).getdata())
            + list(alpha.crop((0, 0, 2, height)).getdata())
            + list(alpha.crop((width - 2, 0, width, height)).getdata())
        )
        edge_pixels.append(sum(value > 16 for value in edge))

    report = {
        "ok": all(value == 0 for value in edge_pixels),
        "input": str(args.input),
        "output": str(args.output),
        "grid": {"columns": args.columns, "rows": args.rows, "frames": len(aligned)},
        "layout_method": args.layout_method,
        "chroma_key": "#%02X%02X%02X" % args.chroma_key,
        "chroma_thresholds": {"inner": args.inner, "outer": args.outer},
        "anchor": {"target_center_x": target_center, "target_bottom": target_bottom},
        "shifts": shifts,
        "bounds": final_bounds,
        "edge_pixels": edge_pixels,
    }
    args.qa_json.parent.mkdir(parents=True, exist_ok=True)
    args.qa_json.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(report, ensure_ascii=False))


if __name__ == "__main__":
    main()
