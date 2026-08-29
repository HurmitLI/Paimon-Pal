#!/usr/bin/env python3
"""Generate three original companion-voice candidates for local review.

The instructions deliberately describe acoustic qualities without naming or
cloning an existing character or a real performer.
"""

from __future__ import annotations

import argparse
import json
import platform
import time
from pathlib import Path

import mlx.core as mx
import numpy as np
from mlx_audio.audio_io import write as audio_write
from mlx_audio.tts.utils import load_model


DEFAULT_TEXT = (
    "嗨，我是你的桌面小伙伴。今天想让我陪你聊聊天，"
    "还是帮你做点事情呀？"
)

CANDIDATES = (
    {
        "id": "A",
        "name": "活泼高音版",
        "instruction": (
            "原创的年轻幻想向导女声。声音明亮轻盈，音高偏高但不尖锐，"
            "语速略快，情绪活泼亲近，带有惊喜感；吐字清晰自然，"
            "像一位悬浮在身边、很有精神的小伙伴。不要模仿任何真实人物或现有角色。"
        ),
    },
    {
        "id": "B",
        "name": "温柔陪伴版",
        "instruction": (
            "原创的年轻幻想伙伴女声。声音轻盈柔和，音高稍高，语速自然，"
            "情绪温暖、关心、可靠，保留一点活泼感；吐字清晰，不做作，"
            "适合安慰和日常陪伴。不要模仿任何真实人物或现有角色。"
        ),
    },
    {
        "id": "C",
        "name": "俏皮精灵版",
        "instruction": (
            "原创的年轻精灵伙伴女声。音色清亮灵动，音高偏高，节奏轻快，"
            "语气俏皮又友好，句尾带一点可爱的上扬和惊喜，但不能刺耳或过度卖萌；"
            "吐字清晰。不要模仿任何真实人物或现有角色。"
        ),
    },
)

REFINED_A_CANDIDATES = (
    {
        "id": "A2",
        "name": "清亮轻鼻音版",
        "instruction": (
            "原创的年轻幻想向导女声。音色非常清亮轻盈，音高明显偏高但不刺耳，"
            "带一点自然、轻微的鼻腔共鸣，声音体量小巧；语速偏快，吐字清楚，"
            "情绪活泼亲近，句子中有明显但自然的高低起伏，减少成熟稳重感。"
            "不要模仿任何真实人物或现有角色。"
        ),
    },
    {
        "id": "A3",
        "name": "高音灵动版",
        "instruction": (
            "原创的年轻悬浮伙伴女声。声线高而轻，清脆通透，带少量空气感，"
            "不能厚重、低沉或成熟；说话节奏轻快，反应感强，语调变化丰富，"
            "像刚发现新鲜事物时兴奋地和朋友分享，中文吐字清晰。"
            "不要模仿任何真实人物或现有角色。"
        ),
    },
    {
        "id": "A4",
        "name": "元气俏皮版",
        "instruction": (
            "原创的年轻奇幻伙伴女声。声音明亮高扬、轻巧有弹性，"
            "语速较快，充满元气和好奇心；重音活泼，句尾自然上扬，"
            "偶尔带一点俏皮的惊喜感，但不要尖叫、不要过度甜腻，吐字清晰。"
            "不要模仿任何真实人物或现有角色。"
        ),
    },
)

CHARACTERFUL_CANDIDATES = (
    {
        "id": "P1",
        "name": "清脆反应感版",
        "instruction": (
            "原创的小体量奇幻伙伴女声。主要用轻巧的高音区和头声，声音清脆、明亮、"
            "带着真实的笑意和很快的反应感；像刚想到什么就立刻凑近朋友回应。"
            "句子中要有短促停连和明显的高低变化，不要字字等长。禁止客服腔、播音腔、"
            "短视频 AI 配音腔和过度标准的普通话，不要模仿任何真实人物或现有角色。"
        ),
    },
    {
        "id": "P2",
        "name": "轻气声小向导版",
        "instruction": (
            "原创的年轻悬浮小向导女声。音高偏高，声音小巧轻盈，带少量自然气声和"
            "轻微鼻腔共鸣，但不能发嗲。说话像在朋友身边即时回应，开头轻快，"
            "重点词会忽然提高，句尾快速收住，不拖长。保留一点不规则的生动节奏。"
            "禁止客服腔、播音腔、均匀机械节奏和通用 AI 女声，不要模仿任何真实人物或现有角色。"
        ),
    },
    {
        "id": "P3",
        "name": "跳跃俏皮版",
        "instruction": (
            "原创的元气童话伙伴女声。音色清亮通透、高而不尖，节奏像小跳步一样有弹性；"
            "每句开头有真实的惊喜反应，中间允许突然加快、轻微笑着说，句尾不做统一上扬。"
            "吐字清楚但不要过度规整，要像角色当场说话，不像后期旁白。"
            "禁止客服腔、短视频 AI 配音腔、成熟御姐音和粘腻撒娇，不要模仿任何真实人物或现有角色。"
        ),
    },
)

CANDIDATE_SETS = {
    "initial": CANDIDATES,
    "refined-a": REFINED_A_CANDIDATES,
    "characterful": CHARACTERFUL_CANDIDATES,
}

SEED_BASES = {
    "initial": 20260829,
    "refined-a": 20260929,
    "characterful": 20261029,
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--text", default=DEFAULT_TEXT)
    parser.add_argument(
        "--candidate-set",
        choices=tuple(CANDIDATE_SETS),
        default="initial",
    )
    parser.add_argument(
        "--candidate-id",
        help="Generate only one candidate from the selected set.",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    model_path = args.model.expanduser().resolve()
    output_path = args.output.expanduser().resolve()
    output_path.mkdir(parents=True, exist_ok=True)

    if not model_path.exists():
        raise SystemExit(f"Model directory does not exist: {model_path}")

    load_started = time.perf_counter()
    model = load_model(model_path)
    load_seconds = time.perf_counter() - load_started

    report: dict[str, object] = {
        "model": str(model_path),
        "platform": platform.platform(),
        "text": args.text,
        "load_seconds": round(load_seconds, 3),
        "candidate_set": args.candidate_set,
        "candidates": [],
    }

    indexed_candidates = list(enumerate(CANDIDATE_SETS[args.candidate_set]))
    if args.candidate_id:
        indexed_candidates = [
            (index, candidate)
            for index, candidate in indexed_candidates
            if candidate["id"] == args.candidate_id
        ]
        if not indexed_candidates:
            available = ", ".join(
                candidate["id"] for candidate in CANDIDATE_SETS[args.candidate_set]
            )
            raise SystemExit(
                f"Unknown candidate id {args.candidate_id!r}; available: {available}"
            )
    seed_base = SEED_BASES[args.candidate_set]
    for index, candidate in indexed_candidates:
        mx.random.seed(seed_base + index)
        started = time.perf_counter()
        results = list(
            model.generate_voice_design(
                text=args.text,
                instruct=candidate["instruction"],
                language="Chinese",
                temperature=0.85,
                top_k=40,
                top_p=0.9,
                repetition_penalty=1.05,
                max_tokens=768,
                verbose=False,
            )
        )
        generation_seconds = time.perf_counter() - started

        if not results:
            raise RuntimeError(f"Candidate {candidate['id']} produced no audio")

        sample_rate = results[0].sample_rate
        audio_parts = [result.audio for result in results]
        audio = audio_parts[0] if len(audio_parts) == 1 else mx.concatenate(audio_parts)
        mx.eval(audio)
        audio_array = np.asarray(audio, dtype=np.float32)
        duration_seconds = len(audio_array) / sample_rate
        filename = f"{candidate['id']}-{candidate['name']}.wav"
        audio_write(output_path / filename, audio_array, sample_rate, format="wav")

        report["candidates"].append(
            {
                **candidate,
                "file": filename,
                "sample_rate": sample_rate,
                "audio_seconds": round(duration_seconds, 3),
                "generation_seconds": round(generation_seconds, 3),
                "real_time_factor": round(
                    duration_seconds / generation_seconds, 3
                ) if generation_seconds else None,
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
