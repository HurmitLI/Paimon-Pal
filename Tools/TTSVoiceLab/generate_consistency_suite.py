#!/usr/bin/env python3
"""Generate the approved A4 voice across representative product messages."""

from __future__ import annotations

import argparse
import json
import time
from pathlib import Path

import mlx.core as mx
import numpy as np
from mlx_audio.audio_io import write as audio_write
from mlx_audio.tts.utils import load_model

from generate_candidates import REFINED_A_CANDIDATES


TEST_LINES = (
    ("01-问候", "旅行者，早上好呀！今天也要一起加油哦。"),
    ("02-安慰", "旅行者，今天是不是有点累呀？先休息一下，我会陪着你的。"),
    ("03-工具确认", "旅行者，一分钟计时已经开始啦，交给我吧！"),
    ("04-计时结束", "旅行者，时间到啦！快回来看看吧。"),
    ("05-打开功能", "旅行者，我已经帮你打开音乐窗口啦。"),
)

A4 = next(candidate for candidate in REFINED_A_CANDIDATES if candidate["id"] == "A4")
A4_SEED = 20260931


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    model_path = args.model.expanduser().resolve()
    output_path = args.output.expanduser().resolve()
    output_path.mkdir(parents=True, exist_ok=True)

    load_started = time.perf_counter()
    model = load_model(model_path)
    load_seconds = time.perf_counter() - load_started

    report: dict[str, object] = {
        "voice": A4,
        "seed": A4_SEED,
        "model": str(model_path),
        "load_seconds": round(load_seconds, 3),
        "samples": [],
    }

    for filename, text in TEST_LINES:
        mx.random.seed(A4_SEED)
        started = time.perf_counter()
        results = list(
            model.generate_voice_design(
                text=text,
                instruct=A4["instruction"],
                language="Chinese",
                temperature=0.85,
                top_k=40,
                top_p=0.9,
                repetition_penalty=1.05,
                max_tokens=512,
                verbose=False,
            )
        )
        generation_seconds = time.perf_counter() - started
        if not results:
            raise RuntimeError(f"No audio generated for {filename}")

        sample_rate = results[0].sample_rate
        parts = [result.audio for result in results]
        audio = parts[0] if len(parts) == 1 else mx.concatenate(parts)
        mx.eval(audio)
        audio_array = np.asarray(audio, dtype=np.float32)
        duration_seconds = len(audio_array) / sample_rate
        audio_file = f"{filename}.wav"
        audio_write(output_path / audio_file, audio_array, sample_rate, format="wav")

        report["samples"].append(
            {
                "file": audio_file,
                "text": text,
                "sample_rate": sample_rate,
                "audio_seconds": round(duration_seconds, 3),
                "generation_seconds": round(generation_seconds, 3),
                "peak_memory_gb": round(mx.get_peak_memory() / 1_000_000_000, 3),
            }
        )

    (output_path / "metrics.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
