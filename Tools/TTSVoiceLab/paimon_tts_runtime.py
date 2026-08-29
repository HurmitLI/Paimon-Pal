#!/usr/bin/env python3
"""Generate one Paimon Pal utterance with the approved fixed P1 voice."""

from __future__ import annotations

import argparse
import json
import os
import time
from pathlib import Path

import mlx.core as mx
import numpy as np
from mlx_audio.audio_io import write as audio_write
from mlx_audio.tts.utils import load_model


PAIMON_VOICE_SEED = 20260931
PAIMON_REFERENCE_TEXT = (
    "嘿，你回来啦！今天想先休息一会儿，"
    "还是让我陪你做点事情呀？"
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", type=Path, required=True)
    parser.add_argument("--reference", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--text", required=True)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    model_path = args.model.expanduser().resolve()
    reference_path = args.reference.expanduser().resolve()
    output_path = args.output.expanduser().resolve()
    text = args.text.strip()

    if not model_path.is_dir():
        raise SystemExit(f"TTS model is missing: {model_path}")
    if not reference_path.is_file():
        raise SystemExit(f"TTS voice reference is missing: {reference_path}")
    if not text or len(text) > 220:
        raise SystemExit("TTS text must contain 1 to 220 characters")

    os.environ.setdefault("HF_HUB_OFFLINE", "1")
    os.environ.setdefault("TRANSFORMERS_OFFLINE", "1")
    os.environ.setdefault("TOKENIZERS_PARALLELISM", "false")
    output_path.parent.mkdir(parents=True, exist_ok=True)
    temporary_path = output_path.with_suffix(".partial.wav")
    temporary_path.unlink(missing_ok=True)

    load_started = time.perf_counter()
    model = load_model(model_path)
    load_seconds = time.perf_counter() - load_started

    # VoiceDesign 会按每句文本重新设计音色，同一描述也可能听起来像不同人。
    # 当前锁定的 mlx-audio 0.5.0 模型包含语音编码器，因此改用已验收 P1
    # 样音做 ICL 参考声纹；后续句子只改变内容和语气，不再重新抽取声纹。
    model.config.tts_model_type = "base"
    mx.random.seed(PAIMON_VOICE_SEED)
    generation_started = time.perf_counter()
    results = list(
        model.generate(
            text=text,
            ref_audio=str(reference_path),
            ref_text=PAIMON_REFERENCE_TEXT,
            lang_code="Chinese",
            temperature=0.65,
            top_k=30,
            top_p=0.8,
            repetition_penalty=1.5,
            max_tokens=768,
            verbose=False,
        )
    )
    generation_seconds = time.perf_counter() - generation_started
    if not results:
        raise RuntimeError("TTS produced no audio")

    sample_rate = results[0].sample_rate
    audio_parts = [result.audio for result in results]
    audio = audio_parts[0] if len(audio_parts) == 1 else mx.concatenate(audio_parts)
    mx.eval(audio)
    audio_array = np.asarray(audio, dtype=np.float32)
    audio_write(temporary_path, audio_array, sample_rate, format="wav")
    temporary_path.replace(output_path)

    report = {
        "output": str(output_path),
        "sample_rate": sample_rate,
        "audio_seconds": round(len(audio_array) / sample_rate, 3),
        "load_seconds": round(load_seconds, 3),
        "generation_seconds": round(generation_seconds, 3),
        "peak_memory_gb": round(mx.get_peak_memory() / 1_000_000_000, 3),
        "voice_mode": "fixed_p1_reference",
    }
    print("PAIMON_TTS_RESULT_BEGIN")
    print(json.dumps(report, ensure_ascii=False))
    print("PAIMON_TTS_RESULT_END")


if __name__ == "__main__":
    main()
