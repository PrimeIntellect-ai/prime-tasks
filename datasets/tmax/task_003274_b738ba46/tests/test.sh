#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "scipy:scipy"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import numpy as np
from scipy.io import wavfile
import pytest


def test_audio_mse():
    processed = "/home/user/processed_audio.wav"
    ref = "/app/.hidden/ref_audio.wav"

    assert os.path.isfile(processed), f"Missing processed audio file: {processed}"
    assert os.path.isfile(ref), f"Missing reference audio file: {ref}"

    try:
        sr1, audio1 = wavfile.read(processed)
        sr2, audio2 = wavfile.read(ref)
    except Exception as e:
        pytest.fail(f"Could not read audio files: {e}")

    assert sr1 == 16000, f"Sample rate mismatch: expected 16000, got {sr1}"
    assert sr1 == sr2, f"Sample rate mismatch with reference: expected {sr2}, got {sr1}"

    # Mono must be encoded as one channel, not averaged by the verifier.
    assert audio1.ndim == 1, f"Processed audio must be mono, got shape {audio1.shape}"
    assert audio2.ndim == 1, f"Reference audio is unexpectedly non-mono: {audio2.shape}"

    # A truncated prefix is not a complete processed recording.
    assert len(audio1) == len(audio2), (
        f"Audio length mismatch: expected {len(audio2)} samples, got {len(audio1)}"
    )
    assert len(audio1) > 0, "Processed audio is empty"

    # Normalize integer audio to float for MSE calculation.
    if np.issubdtype(audio1.dtype, np.integer):
        audio1 = audio1.astype(np.float32) / np.iinfo(audio1.dtype).max
    else:
        audio1 = audio1.astype(np.float32)

    if np.issubdtype(audio2.dtype, np.integer):
        audio2 = audio2.astype(np.float32) / np.iinfo(audio2.dtype).max
    else:
        audio2 = audio2.astype(np.float32)

    mse = np.mean((audio1 - audio2) ** 2)
    assert mse <= 0.005, f"FAIL: MSE {mse} exceeds threshold 0.005"


def test_csv_cleaning():
    clean_path = "/home/user/metadata_clean.csv"
    assert os.path.isfile(clean_path), f"Missing clean CSV file: {clean_path}"

    with open(clean_path, "r", encoding="utf-8") as f:
        lines = f.read().splitlines()

    assert len(lines) > 1, "CSV file is empty or missing data rows"

    expected_lines = [
        "id,timestamp,text",
        "101,00:01:22,this is a normal sentence.",
        "102,00:01:25,this sentence has a newline in it.",
        "103,00:01:30,this is a duplicate sentence.",
        "105,00:01:40,another normal sentence.",
    ]
    assert lines == expected_lines, (
        "Clean CSV does not contain the correctly reconstructed, normalized, "
        "and deduplicated source rows"
    )

    header = lines[0]
    data_lines = lines[1:]
    assert header == "id,timestamp,text", f"Unexpected CSV header: {header}"

    seen_texts = set()
    for i, line in enumerate(data_lines):
        match = re.match(r"^(\d+),(\d{2}:\d{2}:\d{2}(?:\.\d+)?),(.+)$", line)
        assert match is not None, (
            f"Row {i+1} is malformed or contains embedded newlines: {line}"
        )

        row_id, timestamp, text = match.groups()
        assert text == text.lower(), f"Row {i+1} text is not fully lowercase: {text}"
        assert text not in seen_texts, f"Duplicate text found in row {i+1}: {text}"
        seen_texts.add(text)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
