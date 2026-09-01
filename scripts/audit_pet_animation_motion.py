#!/usr/bin/env python3
"""Audit 4x4 pet sprite sheets for visible motion discontinuities.

The audit intentionally checks geometry and transparency rather than trying to
score artistic quality. It catches duplicate frames, sudden silhouette-area
jumps, anchor drift, clipped pixels, and loop seams before an asset reaches the
macOS app.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

from PIL import Image


def frame_cells(sheet: Image.Image, columns: int, rows: int) -> list[Image.Image]:
    width, height = sheet.size
    return [
        sheet.crop(
            (
                round((index % columns) * width / columns),
                round((index // columns) * height / rows),
                round(((index % columns) + 1) * width / columns),
                round(((index // columns) + 1) * height / rows),
            )
        )
        for index in range(columns * rows)
    ]


def visible_pixel_count(alpha: Image.Image, threshold: int) -> int:
    histogram = alpha.histogram()
    return sum(histogram[threshold + 1 :])


def edge_pixel_count(alpha: Image.Image, threshold: int) -> int:
    width, height = alpha.size
    edge = Image.new("L", alpha.size)
    edge.paste(alpha.crop((0, 0, width, 2)), (0, 0))
    edge.paste(alpha.crop((0, height - 2, width, height)), (0, height - 2))
    edge.paste(alpha.crop((0, 2, 2, height - 2)), (0, 2))
    edge.paste(alpha.crop((width - 2, 2, width, height - 2)), (width - 2, 2))
    return visible_pixel_count(edge, threshold)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("sheets", nargs="+", type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--columns", type=int, default=4)
    parser.add_argument("--rows", type=int, default=4)
    parser.add_argument("--alpha-threshold", type=int, default=16)
    parser.add_argument("--max-area-jump", type=float, default=0.08)
    parser.add_argument("--max-center-drift", type=float, default=3.0)
    parser.add_argument("--max-bottom-drift", type=float, default=1.0)
    args = parser.parse_args()

    reports = []
    for path in args.sheets:
        sheet = Image.open(path).convert("RGBA")
        frames = frame_cells(sheet, args.columns, args.rows)
        hashes = [hashlib.sha256(frame.tobytes()).hexdigest() for frame in frames]
        bounds = [frame.getchannel("A").getbbox() for frame in frames]
        if any(bound is None for bound in bounds):
            reports.append({"asset": str(path), "ok": False, "error": "empty frame"})
            continue

        concrete_bounds = [bound for bound in bounds if bound is not None]
        alphas = [frame.getchannel("A") for frame in frames]
        areas = [visible_pixel_count(alpha, args.alpha_threshold) for alpha in alphas]
        centers = [(left + right) / 2 for left, _, right, _ in concrete_bounds]
        bottoms = [bottom for _, _, _, bottom in concrete_bounds]
        area_jumps = [
            abs(areas[(index + 1) % len(areas)] - area) / max(area, 1)
            for index, area in enumerate(areas)
        ]
        edge_pixels = [edge_pixel_count(alpha, args.alpha_threshold) for alpha in alphas]
        duplicate_frames = len(frames) - len(set(hashes))
        center_drift = max(centers) - min(centers)
        bottom_drift = max(bottoms) - min(bottoms)
        maximum_area_jump = max(area_jumps)
        ok = (
            duplicate_frames == 0
            and maximum_area_jump <= args.max_area_jump
            and center_drift <= args.max_center_drift
            and bottom_drift <= args.max_bottom_drift
            and max(edge_pixels) == 0
        )
        reports.append(
            {
                "asset": str(path),
                "ok": ok,
                "frame_count": len(frames),
                "unique_frame_count": len(set(hashes)),
                "duplicate_frames": duplicate_frames,
                "max_adjacent_area_jump": round(maximum_area_jump, 4),
                "loop_area_jump": round(area_jumps[-1], 4),
                "center_drift": round(center_drift, 2),
                "bottom_drift": round(bottom_drift, 2),
                "max_edge_pixels": max(edge_pixels),
            }
        )

    report = {
        "ok": all(item["ok"] for item in reports),
        "criteria": {
            "frames": args.columns * args.rows,
            "duplicates": 0,
            "max_area_jump": args.max_area_jump,
            "max_center_drift": args.max_center_drift,
            "max_bottom_drift": args.max_bottom_drift,
            "max_edge_pixels": 0,
        },
        "assets": reports,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(report, ensure_ascii=False))
    raise SystemExit(0 if report["ok"] else 1)


if __name__ == "__main__":
    main()
