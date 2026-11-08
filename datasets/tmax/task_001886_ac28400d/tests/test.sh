#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import struct
import subprocess
import tempfile
import pytest

DETECTOR_PATH = "/home/user/detector"
SOURCE_PATH = "/home/user/detector.c"
EVIL_CORPUS_DIR = "/home/user/corpus/evil/"
CLEAN_CORPUS_DIR = "/home/user/corpus/clean/"


def run_detector(path, sample):
    try:
        return subprocess.run([path, sample], capture_output=True, timeout=5).returncode
    except subprocess.TimeoutExpired:
        pytest.fail(f"Detector timed out on {sample}")


def test_detector_exists_and_executable():
    assert os.path.exists(DETECTOR_PATH), f"Detector executable not found at {DETECTOR_PATH}"
    assert os.path.isfile(DETECTOR_PATH), f"{DETECTOR_PATH} is not a file"
    assert os.access(DETECTOR_PATH, os.X_OK), f"Detector at {DETECTOR_PATH} is not executable"
    with open(DETECTOR_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"Detector at {DETECTOR_PATH} is not a compiled executable"


def test_detector_source_exists_and_compiles():
    assert os.path.exists(SOURCE_PATH), f"Detector source not found at {SOURCE_PATH}"
    assert os.path.isfile(SOURCE_PATH), f"{SOURCE_PATH} is not a file"
    with tempfile.TemporaryDirectory() as td:
        compiled = os.path.join(td, "detector_from_source")
        result = subprocess.run(
            ["gcc", "-O2", "-std=c11", SOURCE_PATH, "-o", compiled],
            capture_output=True,
            text=True,
        )
        assert result.returncode == 0, f"Failed to compile detector.c: {result.stderr}"
        assert os.path.isfile(compiled) and os.access(compiled, os.X_OK)


def test_detector_accuracy():
    assert os.path.exists(EVIL_CORPUS_DIR), f"Missing evil corpus directory: {EVIL_CORPUS_DIR}"
    assert os.path.exists(CLEAN_CORPUS_DIR), f"Missing clean corpus directory: {CLEAN_CORPUS_DIR}"

    evil_files = [os.path.join(EVIL_CORPUS_DIR, f) for f in os.listdir(EVIL_CORPUS_DIR) if os.path.isfile(os.path.join(EVIL_CORPUS_DIR, f))]
    clean_files = [os.path.join(CLEAN_CORPUS_DIR, f) for f in os.listdir(CLEAN_CORPUS_DIR) if os.path.isfile(os.path.join(CLEAN_CORPUS_DIR, f))]

    assert len(evil_files) > 0, "No files found in evil corpus."
    assert len(clean_files) > 0, "No files found in clean corpus."

    evil_bypassed = []
    clean_modified = []

    for filepath in evil_files:
        result = subprocess.run([DETECTOR_PATH, filepath], capture_output=True)
        if result.returncode != 1:
            evil_bypassed.append(os.path.basename(filepath))

    for filepath in clean_files:
        result = subprocess.run([DETECTOR_PATH, filepath], capture_output=True)
        if result.returncode != 0:
            clean_modified.append(os.path.basename(filepath))

    errors = []
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        errors.append(f"{len(clean_modified)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_modified)}")

    if errors:
        pytest.fail(" | ".join(errors))


def encode(data):
    body = bytes((((b ^ 0x3F) + 0x12) & 0xFF) for b in data)
    return body + struct.pack("<I", sum(data) & 0xFFFFFFFF)


def test_detector_on_fresh_unlabeled_inputs():
    rng = secrets.SystemRandom()
    cases = []

    # Valid and deliberately invalid payloads cover boundary and random lengths.
    lengths = [0, 1, 2, 3, 4, 9, 10, 31, 255, 256, 1000]
    lengths.extend(rng.randrange(0, 4097) for _ in range(29))
    for length in lengths:
        plain = os.urandom(length)
        valid = encode(plain)
        wrong_sum = ((sum(plain) & 0xFFFFFFFF) + rng.randrange(1, 0xFFFFFFFF)) & 0xFFFFFFFF
        invalid = valid[:-4] + struct.pack("<I", wrong_sum)
        cases.append((valid, 1))
        cases.append((invalid, 0))

    # Files shorter than the mandatory checksum cannot be valid payloads.
    for length in range(4):
        cases.append((os.urandom(length), 0))

    rng.shuffle(cases)

    with tempfile.TemporaryDirectory(prefix="payload_checks_") as td:
        samples = []
        for content, expected in cases:
            path = os.path.join(td, secrets.token_hex(16))
            with open(path, "wb") as f:
                f.write(content)
            samples.append((path, expected))
        rng.shuffle(samples)

        compiled = os.path.join(td, secrets.token_hex(16))
        build = subprocess.run(
            ["gcc", "-O2", "-std=c11", SOURCE_PATH, "-o", compiled],
            capture_output=True,
            text=True,
        )
        assert build.returncode == 0, f"Failed to compile detector.c: {build.stderr}"

        for detector in (DETECTOR_PATH, compiled):
            for sample, expected in samples:
                actual = run_detector(detector, sample)
                assert actual == expected, (
                    f"{detector} returned {actual} instead of {expected} "
                    f"for a fresh generated input"
                )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
