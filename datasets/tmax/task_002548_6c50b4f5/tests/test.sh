#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import glob
import random
import struct
import subprocess
import tempfile
import uuid
import wave
import pytest

SCRIPT_PATH = "/home/user/detector.py"
CLEAN_CORPUS_DIR = "/app/corpus/clean"
EVIL_CORPUS_DIR = "/app/corpus/evil"

def test_detector_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"The required script was not found at {SCRIPT_PATH}"

def test_adversarial_corpus():
    assert os.path.isfile(SCRIPT_PATH), f"Script missing at {SCRIPT_PATH}"

    clean_files = glob.glob(os.path.join(CLEAN_CORPUS_DIR, "*.wav"))
    evil_files = glob.glob(os.path.join(EVIL_CORPUS_DIR, "*.wav"))

    assert len(clean_files) > 0, f"No clean files found in {CLEAN_CORPUS_DIR}"
    assert len(evil_files) > 0, f"No evil files found in {EVIL_CORPUS_DIR}"

    failed_clean = []
    for clean_file in clean_files:
        result = subprocess.run(["python3", SCRIPT_PATH, clean_file], capture_output=True)
        if result.returncode != 0:
            failed_clean.append(os.path.basename(clean_file))

    failed_evil = []
    for evil_file in evil_files:
        result = subprocess.run(["python3", SCRIPT_PATH, evil_file], capture_output=True)
        if result.returncode == 0:
            failed_evil.append(os.path.basename(evil_file))

    errors = []
    if failed_clean:
        errors.append(f"{len(failed_clean)} of {len(clean_files)} clean files modified/rejected: {', '.join(failed_clean)}")
    if failed_evil:
        errors.append(f"{len(failed_evil)} of {len(evil_files)} evil files bypassed: {', '.join(failed_evil)}")

    assert not errors, "Adversarial corpus validation failed:\n" + "\n".join(errors)

def _write_mono_wav(path, sample_rate, zero_runs):
    frame_count = sample_rate // 3
    samples = [((i * 7919) % 30000) + 1 for i in range(frame_count)]
    for start, length in zero_runs:
        samples[start:start + length] = [0] * length

    with wave.open(path, "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(sample_rate)
        wav.writeframes(struct.pack(f"<{len(samples)}h", *samples))

def test_generated_zero_run_boundary_cases():
    assert os.path.isfile(SCRIPT_PATH), f"Script missing at {SCRIPT_PATH}"

    cases = []
    with tempfile.TemporaryDirectory() as temp_dir:
        for sample_rate in (8000, 11025, 44100):
            # Smallest integral sample count whose duration is at least 50 ms.
            threshold = (sample_rate * 50 + 999) // 1000
            start = sample_rate // 10
            definitions = [
                ([], False),
                ([(start, threshold - 1)], False),
                ([(start, threshold)], True),
                ([(start, threshold - 1), (start + threshold + 7, threshold - 1)], False),
            ]
            for zero_runs, unsafe in definitions:
                path = os.path.join(temp_dir, f"{uuid.uuid4().hex}.wav")
                _write_mono_wav(path, sample_rate, zero_runs)
                cases.append((path, unsafe, sample_rate, zero_runs))

        random.SystemRandom().shuffle(cases)
        errors = []
        for path, unsafe, sample_rate, zero_runs in cases:
            try:
                result = subprocess.run(
                    ["python3", SCRIPT_PATH, os.path.abspath(path)],
                    capture_output=True,
                    timeout=10,
                )
            except subprocess.TimeoutExpired:
                errors.append(f"detector timed out for generated {sample_rate} Hz WAV")
                continue

            actually_unsafe = result.returncode != 0
            if actually_unsafe != unsafe:
                run_lengths = [length for _, length in zero_runs]
                errors.append(
                    f"wrong result for generated {sample_rate} Hz WAV with "
                    f"zero runs {run_lengths}: expected unsafe={unsafe}, "
                    f"return code={result.returncode}"
                )

        assert not errors, "Generated WAV validation failed:\n" + "\n".join(errors)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
