#!/usr/bin/env python3
"""Render a processed 4xN animation sheet as a review GIF."""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image


def boxes(width: int, height: int, columns: int, rows: int):
    for index in range(columns * rows):
        column = index % columns
        row = index // columns
        yield (
            round(column * width / columns),
            round(row * height / rows),
            round((column + 1) * width / columns),
            round((row + 1) * height / rows),
        )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--columns", type=int, default=4)
    parser.add_argument("--rows", type=int, default=4)
    parser.add_argument("--fps", type=int, default=12)
    parser.add_argument("--size", type=int, default=220)
    args = parser.parse_args()

    sheet = Image.open(args.input).convert("RGBA")
    frames = []
    for box in boxes(sheet.width, sheet.height, args.columns, args.rows):
        sprite = sheet.crop(box)
        canvas = Image.new("RGBA", (args.size, args.size), (28, 30, 34, 255))
        sprite.thumbnail((args.size - 16, args.size - 16), Image.Resampling.LANCZOS)
        canvas.alpha_composite(
            sprite,
            ((args.size - sprite.width) // 2, (args.size - sprite.height) // 2),
        )
        frames.append(canvas.convert("RGB"))

    args.output.parent.mkdir(parents=True, exist_ok=True)
    frames[0].save(
        args.output,
        save_all=True,
        append_images=frames[1:],
        duration=round(1000 / max(args.fps, 1)),
        loop=0,
        optimize=False,
    )
    print(args.output)


if __name__ == "__main__":
    main()
