#!/usr/bin/env python3
"""Generate Paimon Pal speech, either once or as a persistent streaming worker."""

from __future__ import annotations

import argparse
import base64
import json
import os
import queue
import sys
import threading
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
PAIMON_PRIME_TEXT = "嗯，准备好了。"
# Qwen3-TTS can technically emit at 0.32s, but its first partial decode has too
# little future context and can distort the opening one or two Chinese syllables.
# 0.80s still feels immediate while giving the first phonemes enough context.
STREAMING_INTERVAL_SECONDS = 0.80


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", type=Path, required=True)
    parser.add_argument("--reference", type=Path, required=True)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--text")
    parser.add_argument("--server", action="store_true")
    return parser.parse_args()


def emit(payload: dict) -> None:
    print(json.dumps(payload, ensure_ascii=False, separators=(",", ":")), flush=True)


def validate_paths(model_path: Path, reference_path: Path) -> None:
    if not model_path.is_dir():
        raise SystemExit(f"TTS model is missing: {model_path}")
    if not reference_path.is_file():
        raise SystemExit(f"TTS voice reference is missing: {reference_path}")


def load_paimon_model(model_path: Path):
    mx.random.seed(PAIMON_VOICE_SEED)
    model = load_model(model_path)
    # Lock the accepted P1 reference voice. VoiceDesign can vary between turns.
    model.config.tts_model_type = "base"
    return model


def generation_options(reference_path: Path) -> dict:
    return {
        "ref_audio": str(reference_path),
        "ref_text": PAIMON_REFERENCE_TEXT,
        "lang_code": "Chinese",
        "temperature": 0.65,
        "top_k": 30,
        "top_p": 0.8,
        "repetition_penalty": 1.5,
        "max_tokens": 768,
        "verbose": False,
    }


def reset_voice_sampling() -> None:
    """Keep the accepted P1 timbre stable across every visible utterance."""
    mx.random.seed(PAIMON_VOICE_SEED)


def prime_streaming_voice(model, reference_path: Path) -> dict:
    """Run the first streaming inference silently so users never hear cold-start audio."""
    started = time.perf_counter()
    audio_samples = 0
    sample_rate = 24000
    reset_voice_sampling()
    for result in model.generate(
        text=PAIMON_PRIME_TEXT,
        stream=True,
        streaming_interval=STREAMING_INTERVAL_SECONDS,
        **generation_options(reference_path),
    ):
        mx.eval(result.audio)
        audio_samples += int(np.asarray(result.audio).size)
        sample_rate = int(result.sample_rate)
    # The priming sentence must not advance the sampling state used by the first
    # user-visible sentence. Reset again so first and later replies share one voice.
    reset_voice_sampling()
    return {
        "primed": audio_samples > 0,
        "prime_seconds": round(time.perf_counter() - started, 3),
        "prime_audio_seconds": round(audio_samples / sample_rate, 3) if sample_rate else 0,
    }


def audio_to_pcm16(audio) -> tuple[bytes, int]:
    mx.eval(audio)
    values = np.asarray(audio, dtype=np.float32).reshape(-1)
    pcm = (np.clip(values, -1.0, 1.0) * 32767.0).astype("<i2", copy=False)
    return pcm.tobytes(), len(values)


def run_once(args: argparse.Namespace, model_path: Path, reference_path: Path) -> None:
    if args.output is None or not args.text:
        raise SystemExit("--output and --text are required unless --server is used")
    output_path = args.output.expanduser().resolve()
    text = args.text.strip()
    if not text or len(text) > 220:
        raise SystemExit("TTS text must contain 1 to 220 characters")

    output_path.parent.mkdir(parents=True, exist_ok=True)
    temporary_path = output_path.with_suffix(".partial.wav")
    temporary_path.unlink(missing_ok=True)

    load_started = time.perf_counter()
    model = load_paimon_model(model_path)
    load_seconds = time.perf_counter() - load_started
    generation_started = time.perf_counter()
    reset_voice_sampling()
    results = list(model.generate(text=text, **generation_options(reference_path)))
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


class StreamingWorker:
    def __init__(self, model_path: Path, reference_path: Path) -> None:
        self.model_path = model_path
        self.reference_path = reference_path
        self.commands: queue.Queue[dict] = queue.Queue()
        self.cancel_event = threading.Event()
        self.shutdown_event = threading.Event()

    def read_commands(self) -> None:
        for raw_line in sys.stdin:
            try:
                command = json.loads(raw_line)
            except (TypeError, ValueError):
                continue
            command_type = command.get("type")
            if command_type in {"cancel", "shutdown", "synthesize"}:
                self.cancel_event.set()
            if command_type == "shutdown":
                self.shutdown_event.set()
            self.commands.put(command)

    def next_synthesis(self) -> dict | None:
        command = self.commands.get()
        if command.get("type") == "shutdown":
            return None
        if command.get("type") != "synthesize":
            return {}
        # A new sentence supersedes older queued sentences. This keeps replies snappy.
        latest = command
        while True:
            try:
                candidate = self.commands.get_nowait()
            except queue.Empty:
                break
            if candidate.get("type") == "shutdown":
                self.shutdown_event.set()
                return None
            if candidate.get("type") == "synthesize":
                latest = candidate
        return latest

    def run(self) -> None:
        reader = threading.Thread(target=self.read_commands, name="tts-command-reader", daemon=True)
        reader.start()
        load_started = time.perf_counter()
        model = load_paimon_model(self.model_path)
        load_seconds = time.perf_counter() - load_started
        prime_result = prime_streaming_voice(model, self.reference_path)
        emit({
            "type": "ready",
            "load_seconds": round(load_seconds, 3),
            **prime_result,
        })

        while not self.shutdown_event.is_set():
            command = self.next_synthesis()
            if command is None:
                break
            if not command:
                continue
            request_id = str(command.get("id") or "")
            text = str(command.get("text") or "").strip()[:220]
            if not request_id or not text:
                emit({"type": "error", "id": request_id, "error": "empty_text"})
                continue

            self.cancel_event.clear()
            emit({"type": "start", "id": request_id})
            started = time.perf_counter()
            audio_bytes = 0
            audio_samples = 0
            first_chunk_ms = None
            try:
                reset_voice_sampling()
                results = model.generate(
                    text=text,
                    stream=True,
                    streaming_interval=STREAMING_INTERVAL_SECONDS,
                    **generation_options(self.reference_path),
                )
                for sequence, result in enumerate(results):
                    if self.cancel_event.is_set() or self.shutdown_event.is_set():
                        emit({"type": "cancelled", "id": request_id})
                        break
                    pcm, samples = audio_to_pcm16(result.audio)
                    if not pcm:
                        continue
                    if first_chunk_ms is None:
                        first_chunk_ms = round((time.perf_counter() - started) * 1000)
                    audio_bytes += len(pcm)
                    audio_samples += samples
                    emit({
                        "type": "chunk",
                        "id": request_id,
                        "sequence": sequence,
                        "sample_rate": int(result.sample_rate),
                        "pcm16_base64": base64.b64encode(pcm).decode("ascii"),
                    })
                else:
                    emit({
                        "type": "done",
                        "id": request_id,
                        "audio_bytes": audio_bytes,
                        "audio_seconds": round(audio_samples / 24000, 3),
                        "first_chunk_ms": first_chunk_ms,
                        "generation_seconds": round(time.perf_counter() - started, 3),
                    })
            except Exception as error:  # protocol must survive a failed utterance
                emit({"type": "error", "id": request_id, "error": str(error)[:400]})
            finally:
                mx.clear_cache()


def main() -> None:
    args = parse_args()
    model_path = args.model.expanduser().resolve()
    reference_path = args.reference.expanduser().resolve()
    validate_paths(model_path, reference_path)
    os.environ.setdefault("HF_HUB_OFFLINE", "1")
    os.environ.setdefault("TRANSFORMERS_OFFLINE", "1")
    os.environ.setdefault("TOKENIZERS_PARALLELISM", "false")
    if args.server:
        StreamingWorker(model_path, reference_path).run()
    else:
        run_once(args, model_path, reference_path)


if __name__ == "__main__":
    main()
