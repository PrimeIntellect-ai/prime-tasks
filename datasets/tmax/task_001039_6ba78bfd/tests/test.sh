#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import secrets
import struct
import subprocess
import sys
import tempfile

import pytest

DETECTOR_PATH = "/app/detector.py"


def run_detector(input_dir, output_json):
    assert os.path.isfile(DETECTOR_PATH), f"Detector script not found at {DETECTOR_PATH}"
    if os.path.exists(output_json):
        os.remove(output_json)

    try:
        subprocess.run(
            [sys.executable, DETECTOR_PATH, input_dir, output_json],
            check=True,
            capture_output=True,
            text=True,
            timeout=30,
        )
    except subprocess.CalledProcessError as e:
        pytest.fail(
            f"Detector script failed with exit code {e.returncode}.\n"
            f"STDOUT: {e.stdout}\nSTDERR: {e.stderr}"
        )
    except subprocess.TimeoutExpired:
        pytest.fail("Detector script timed out after 30 seconds.")

    assert os.path.isfile(output_json), f"Output JSON not found at {output_json}"
    try:
        with open(output_json, "r") as f:
            results = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"Output file {output_json} is not valid JSON.")

    assert isinstance(results, dict), (
        f"Expected JSON output to be a dictionary, got {type(results).__name__}"
    )
    return results


def test_detector_results():
    input_dir = "/app/corpora/eval_mixed"
    output_json = "/tmp/results.json"
    clean_dir = "/app/corpora/clean"
    evil_dir = "/app/corpora/evil"

    results = run_detector(input_dir, output_json)

    clean_files = [f for f in os.listdir(clean_dir) if f.endswith(".wav")]
    evil_files = [f for f in os.listdir(evil_dir) if f.endswith(".wav")]

    bypassed_evil = []
    modified_clean = []

    for f in evil_files:
        if results.get(f) != "REJECT":
            bypassed_evil.append(f)

    for f in clean_files:
        if results.get(f) != "ACCEPT":
            modified_clean.append(f)

    error_messages = []
    if bypassed_evil:
        error_messages.append(
            f"{len(bypassed_evil)} of {len(evil_files)} evil bypassed: "
            + ", ".join(bypassed_evil)
        )
    if modified_clean:
        error_messages.append(
            f"{len(modified_clean)} of {len(clean_files)} clean modified: "
            + ", ".join(modified_clean)
        )

    if error_messages:
        pytest.fail(" | ".join(error_messages))


def valid_chunk(chunk_id, payload):
    assert len(chunk_id) == 4
    padding = b"\x00" if len(payload) % 2 else b""
    return chunk_id + struct.pack("<I", len(payload)) + payload + padding


def wav_bytes(extra_chunks=b""):
    fmt_payload = struct.pack(
        "<HHIIHH", 1, 1, 44100, 88200, 2, 16
    )
    body = b"WAVE" + valid_chunk(b"fmt ", fmt_payload)
    body += valid_chunk(b"data", b"")
    body += extra_chunks
    return b"RIFF" + struct.pack("<I", len(body)) + body


def malicious_acid(size):
    assert -(2**31) <= size < 0
    return b"acid" + struct.pack("<i", size)


def test_detector_on_runtime_generated_corpus():
    nonce = secrets.token_hex(12)
    odd_prefix = valid_chunk(b"JUNK", b"abc")
    fake_marker = valid_chunk(
        b"JUNK", b"prefix-acid" + struct.pack("<i", -1) + b"-payload"
    )

    cases = [
        (wav_bytes(), "ACCEPT"),
        (wav_bytes(valid_chunk(b"acid", b"")), "ACCEPT"),
        (wav_bytes(valid_chunk(b"acid", secrets.token_bytes(19))), "ACCEPT"),
        (wav_bytes(fake_marker), "ACCEPT"),
        (wav_bytes(b"ACID" + struct.pack("<i", -7)), "ACCEPT"),
        (wav_bytes(b"JUNK" + struct.pack("<i", -1)), "ACCEPT"),
        (wav_bytes(malicious_acid(-1)), "REJECT"),
        (wav_bytes(odd_prefix + malicious_acid(-50)), "REJECT"),
        (wav_bytes(malicious_acid(-(2**31))), "REJECT"),
    ]
    random.SystemRandom().shuffle(cases)

    with tempfile.TemporaryDirectory(prefix="wav_eval_") as input_dir:
        expected = {}
        for index, (content, label) in enumerate(cases):
            filename = f"{nonce}_{secrets.token_hex(8)}_{index}.wav"
            with open(os.path.join(input_dir, filename), "wb") as f:
                f.write(content)
            expected[filename] = label

        output_json = os.path.join(tempfile.gettempdir(), f"detector_{nonce}.json")
        results = run_detector(input_dir, output_json)
        assert set(results) == set(expected), (
            "Output must contain exactly one entry for every runtime-generated WAV file"
        )
        assert results == expected
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
