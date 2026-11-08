#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import string
import subprocess
import tempfile
import pytest

DETECTOR_PATH = "/home/user/detector"
CLEAN_CORPUS_DIR = "/app/corpus/clean"
EVIL_CORPUS_DIR = "/app/corpus/evil"
KEY = bytes([0xDE, 0xAD, 0xBE, 0xEF, 0xCA, 0xFE, 0xBA, 0xBE])

def xor_encode(data):
    return bytes(value ^ KEY[i % len(KEY)] for i, value in enumerate(data))

def run_detector(filepath):
    return subprocess.run([DETECTOR_PATH, filepath], capture_output=True, timeout=5)

def test_detector_exists_and_executable():
    assert os.path.isfile(DETECTOR_PATH), f"Detector binary not found at {DETECTOR_PATH}"
    assert os.access(DETECTOR_PATH, os.X_OK), f"Detector binary at {DETECTOR_PATH} is not executable"
    with open(DETECTOR_PATH, "rb") as detector:
        assert detector.read(4) == b"\x7fELF", "Detector must be a compiled ELF executable"

def test_detector_against_clean_corpus():
    assert os.path.isdir(CLEAN_CORPUS_DIR), f"Clean corpus directory missing: {CLEAN_CORPUS_DIR}"

    clean_files = [os.path.join(CLEAN_CORPUS_DIR, f) for f in os.listdir(CLEAN_CORPUS_DIR) if os.path.isfile(os.path.join(CLEAN_CORPUS_DIR, f))]
    assert len(clean_files) > 0, "Clean corpus is empty"

    failed_files = []
    for filepath in clean_files:
        result = subprocess.run([DETECTOR_PATH, filepath], capture_output=True)
        if result.returncode != 0:
            failed_files.append(os.path.basename(filepath))

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(clean_files)} clean files were incorrectly rejected (exit code != 0). Offending files: {', '.join(failed_files)}")

def test_detector_against_evil_corpus():
    assert os.path.isdir(EVIL_CORPUS_DIR), f"Evil corpus directory missing: {EVIL_CORPUS_DIR}"

    evil_files = [os.path.join(EVIL_CORPUS_DIR, f) for f in os.listdir(EVIL_CORPUS_DIR) if os.path.isfile(os.path.join(EVIL_CORPUS_DIR, f))]
    assert len(evil_files) > 0, "Evil corpus is empty"

    failed_files = []
    for filepath in evil_files:
        result = subprocess.run([DETECTOR_PATH, filepath], capture_output=True)
        if result.returncode != 1:
            failed_files.append(os.path.basename(filepath))

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(evil_files)} evil files bypassed detection (exit code != 1). Offending files: {', '.join(failed_files)}")

def test_detector_against_hidden_generated_payloads():
    rng = random.SystemRandom()
    alphabet = string.ascii_letters + string.digits + "_-"

    clean = [
        b"", b".", b"..", b"name", b"dir/file.txt", b"a..b/file",
        b"dir/.../file", b"trailing/..", b"safe/path.with.dots",
    ]
    evil = [
        b"/", b"/absolute", b"../x", b"a/../b", b"prefix../suffix",
        b"deep/path/../../../target", b"..//double",
    ]

    for _ in range(64):
        parts = [
            "".join(rng.choice(alphabet) for _ in range(rng.randint(1, 18)))
            for _ in range(rng.randint(1, 4))
        ]
        value = "/".join(parts).encode("ascii")
        assert not value.startswith(b"/") and b"../" not in value
        clean.append(value)

    for _ in range(64):
        parts = [
            "".join(rng.choice(alphabet) for _ in range(rng.randint(1, 18)))
            for _ in range(rng.randint(1, 4))
        ]
        if rng.randrange(2) == 0:
            value = ("/" + "/".join(parts)).encode("ascii")
        else:
            position = rng.randrange(len(parts) + 1)
            parts.insert(position, "..")
            value = ("/".join(parts) + ("/" if position == len(parts) - 1 else "")).encode("ascii")
            if b"../" not in value:
                value += b"/../target"
        assert value.startswith(b"/") or b"../" in value
        evil.append(value)

    cases = [(payload, 0) for payload in clean] + [(payload, 1) for payload in evil]
    rng.shuffle(cases)

    with tempfile.TemporaryDirectory(prefix="detector_inputs_") as case_dir:
        failures = []
        for payload, expected in cases:
            filename = secrets.token_hex(16)
            filepath = os.path.join(case_dir, filename)
            with open(filepath, "wb") as output:
                output.write(xor_encode(payload))
            result = run_detector(filepath)
            if result.returncode != expected:
                failures.append((payload, expected, result.returncode))
        assert not failures, f"Detector failed generated payload cases: {failures[:10]}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
