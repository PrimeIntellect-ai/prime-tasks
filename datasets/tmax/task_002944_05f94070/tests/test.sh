#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import random
import secrets
import subprocess
import tempfile

import pytest

DETECTOR_PATH = "/home/user/detector"
CLEAN_CORPUS_DIR = "/app/corpus/clean/"
EVIL_CORPUS_DIR = "/app/corpus/evil/"


def run_detector(path):
    return subprocess.run(
        [DETECTOR_PATH, path],
        capture_output=True,
        timeout=3,
    ).returncode


def expected_result(data):
    if len(data) < 6:
        return 0
    length = int.from_bytes(data[4:6], "little")
    payload_read = data[6:6 + length]
    return int(length > 64 and len(payload_read) > 64 and payload_read[64] == 0xFF)


def make_record(magic, length, payload):
    return magic + length.to_bytes(2, "little") + payload


def test_detector_exists_and_executable():
    assert os.path.exists(DETECTOR_PATH), f"Detector binary not found at {DETECTOR_PATH}"
    assert os.path.isfile(DETECTOR_PATH), f"Detector path {DETECTOR_PATH} is not a file"
    assert os.access(DETECTOR_PATH, os.X_OK), f"Detector binary at {DETECTOR_PATH} is not executable"
    with open(DETECTOR_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Detector must be a compiled executable"


def test_detector_against_corpora():
    clean_files = glob.glob(os.path.join(CLEAN_CORPUS_DIR, "*"))
    evil_files = glob.glob(os.path.join(EVIL_CORPUS_DIR, "*"))

    assert len(clean_files) > 0, f"No clean files found in {CLEAN_CORPUS_DIR}"
    assert len(evil_files) > 0, f"No evil files found in {EVIL_CORPUS_DIR}"

    clean_failures = []
    for f in clean_files:
        if run_detector(f) != 0:
            clean_failures.append(os.path.basename(f))

    evil_failures = []
    for f in evil_files:
        if run_detector(f) != 1:
            evil_failures.append(os.path.basename(f))

    error_messages = []
    if evil_failures:
        error_messages.append(f"{len(evil_failures)} of {len(evil_files)} evil bypassed: {', '.join(evil_failures)}")
    if clean_failures:
        error_messages.append(f"{len(clean_failures)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_failures)}")

    if error_messages:
        pytest.fail(" | ".join(error_messages))


def test_detector_against_generated_hidden_suite():
    cases = [
        b"",
        b"DATA",
        b"DATA\x41",
        make_record(b"DATA", 0, b""),
        make_record(b"DATA", 64, b"A" * 64),
        make_record(b"DATA", 65, b"A" * 64),
        make_record(b"DATA", 65, b"A" * 64 + b"\xff"),
        make_record(b"DATA", 70, b"A" * 63 + b"\xff" + b"A" * 6),
        make_record(b"DATA", 70, b"A" * 64 + b"\xfe" + b"A" * 5),
        make_record(b"DATA", 70, b"A" * 64 + b"\xff" + b"A" * 5),
        make_record(b"NOPE", 70, b"B" * 64 + b"\xff" + b"B" * 5),
        make_record(b"DATA", 65535, b"C" * 64 + b"\xff"),
        make_record(b"DATA", 1, b"D" * 64 + b"\xff" + b"D" * 20),
    ]

    for i in range(120):
        mode = i % 5
        magic = os.urandom(4)
        if mode == 0:
            length = 65 + secrets.randbelow(500)
            available = 65 + secrets.randbelow(500)
            payload = bytearray(os.urandom(available))
            payload[64] = 0xFF
        elif mode == 1:
            length = 65 + secrets.randbelow(500)
            available = secrets.randbelow(65)
            payload = bytearray(os.urandom(available))
        elif mode == 2:
            length = 65 + secrets.randbelow(500)
            available = 65 + secrets.randbelow(500)
            payload = bytearray(os.urandom(available))
            payload[64] = secrets.randbelow(255)
        elif mode == 3:
            length = secrets.randbelow(65)
            available = 65 + secrets.randbelow(300)
            payload = bytearray(os.urandom(available))
            payload[64] = 0xFF
        else:
            length = secrets.randbelow(65536)
            available = secrets.randbelow(600)
            payload = bytearray(os.urandom(available))
        cases.append(make_record(magic, length, bytes(payload)))

    random.SystemRandom().shuffle(cases)
    failures = []
    with tempfile.TemporaryDirectory(prefix="detector-hidden-") as suite_dir:
        for data in cases:
            name = secrets.token_hex(16) + ".bin"
            path = os.path.join(suite_dir, name)
            with open(path, "wb") as f:
                f.write(data)
            expected = expected_result(data)
            actual = run_detector(path)
            if actual != expected:
                failures.append(f"{name}: expected {expected}, got {actual}")

    assert not failures, "Generated-suite failures: " + " | ".join(failures[:10])
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
