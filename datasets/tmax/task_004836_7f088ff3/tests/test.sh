#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import random
import subprocess
import tempfile
import uuid

import pytest

DETECTOR_PATH = "/home/user/detector"
SOURCE_PATH = "/home/user/detector.cpp"
EVIL_CORPUS_DIR = "/app/corpus/evil"
CLEAN_CORPUS_DIR = "/app/corpus/clean"


def run_detector(executable, filepath):
    try:
        return subprocess.run(
            [executable, filepath], capture_output=True, timeout=3
        ).returncode
    except subprocess.TimeoutExpired:
        pytest.fail(f"Detector timed out on {filepath}")


def test_detector_exists_and_executable():
    assert os.path.isfile(DETECTOR_PATH), f"Detector executable not found at {DETECTOR_PATH}"
    assert os.access(DETECTOR_PATH, os.X_OK), f"Detector at {DETECTOR_PATH} is not executable"
    with open(DETECTOR_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Detector must be a compiled executable"


def test_cpp_source_exists_and_compiles():
    assert os.path.isfile(SOURCE_PATH), f"C++ source not found at {SOURCE_PATH}"
    result = subprocess.run(
        ["g++", "-std=c++17", "-O2", SOURCE_PATH, "-o", "/tmp/detector_from_source"],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"detector.cpp did not compile as C++: {result.stderr}"
    assert os.path.isfile("/tmp/detector_from_source")
    assert os.access("/tmp/detector_from_source", os.X_OK)


def test_adversarial_corpus_evil():
    evil_files = glob.glob(os.path.join(EVIL_CORPUS_DIR, "*"))
    assert len(evil_files) > 0, f"No files found in evil corpus directory {EVIL_CORPUS_DIR}"

    bypassed_files = []
    for filepath in evil_files:
        result = subprocess.run([DETECTOR_PATH, filepath], capture_output=True)
        if result.returncode != 1:
            bypassed_files.append(os.path.basename(filepath))

    if bypassed_files:
        pytest.fail(f"{len(bypassed_files)} of {len(evil_files)} evil bypassed. Offending files: {', '.join(bypassed_files)}")


def test_adversarial_corpus_clean():
    clean_files = glob.glob(os.path.join(CLEAN_CORPUS_DIR, "*"))
    assert len(clean_files) > 0, f"No files found in clean corpus directory {CLEAN_CORPUS_DIR}"

    modified_files = []
    for filepath in clean_files:
        result = subprocess.run([DETECTOR_PATH, filepath], capture_output=True)
        if result.returncode != 0:
            modified_files.append(os.path.basename(filepath))

    if modified_files:
        pytest.fail(f"{len(modified_files)} of {len(clean_files)} clean modified/flagged. Offending files: {', '.join(modified_files)}")


def expected_code(payload):
    if len(payload) < 6:
        return 0
    if payload[:4] != b"\xda\x7a\xbe\xef":
        return 0
    declared = int.from_bytes(payload[4:6], "little")
    return 1 if declared > len(payload) - 6 else 0


def test_generated_payloads_at_unrelated_paths():
    rng = random.SystemRandom()
    magic = b"\xda\x7a\xbe\xef"
    payloads = [
        b"",
        b"\xda",
        magic,
        magic + b"\x01",
        magic + (0).to_bytes(2, "little"),
        magic + (1).to_bytes(2, "little"),
        magic + (1).to_bytes(2, "little") + b"X",
        magic + (2).to_bytes(2, "little") + b"X",
        magic + (2).to_bytes(2, "little") + b"XY",
        magic + (1).to_bytes(2, "little") + b"XYZ",
        magic + (65535).to_bytes(2, "little") + os.urandom(32),
        b"NOPE" + (65535).to_bytes(2, "little"),
        b"NOPE" + (65535).to_bytes(2, "little") + os.urandom(20),
    ]

    for _ in range(100):
        body_len = rng.randrange(0, 257)
        body = os.urandom(body_len)
        declared = rng.randrange(0, 65536)
        if rng.randrange(3) != 0:
            header = magic
        else:
            header = os.urandom(4)
            if header == magic:
                header = b"BAD!"
        payloads.append(header + declared.to_bytes(2, "little") + body)

    rng.shuffle(payloads)
    with tempfile.TemporaryDirectory(prefix="payload-validation-") as directory:
        for payload in payloads:
            filepath = os.path.join(directory, uuid.uuid4().hex)
            with open(filepath, "wb") as f:
                f.write(payload)
            wanted = expected_code(payload)
            for executable in (DETECTOR_PATH, "/tmp/detector_from_source"):
                actual = run_detector(executable, filepath)
                assert actual == wanted, (
                    f"{executable} returned {actual}, expected {wanted}, "
                    f"for a generated payload of {len(payload)} bytes"
                )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
