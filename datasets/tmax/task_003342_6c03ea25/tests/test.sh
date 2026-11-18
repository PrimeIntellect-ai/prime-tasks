#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import struct
import subprocess
import tempfile
import pytest

FILTER_GO = "/home/user/filter.go"
FILTER_BIN = "/tmp/submitted_filter"
CLEAN_CORPUS = "/app/corpus/clean"
EVIL_CORPUS = "/app/corpus/evil"

@pytest.fixture(scope="session")
def compiled_filter():
    assert os.path.isfile(FILTER_GO), f"File not found: {FILTER_GO}"
    result = subprocess.run(
        ["go", "build", "-o", FILTER_BIN, FILTER_GO],
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, f"Failed to compile {FILTER_GO}: {result.stderr}"
    return FILTER_BIN

def run_filter(binary, path):
    result = subprocess.run(
        [binary, path], capture_output=True, text=True, timeout=10
    )
    return result.returncode, result.stdout.strip()

def test_filter_go_exists():
    assert os.path.isfile(FILTER_GO), f"File not found: {FILTER_GO}"

def test_adversarial_corpus(compiled_filter):
    assert os.path.isfile(FILTER_GO), f"Pre-requisite failed: {FILTER_GO} does not exist"

    clean_files = [os.path.join(CLEAN_CORPUS, f) for f in os.listdir(CLEAN_CORPUS)]
    evil_files = [os.path.join(EVIL_CORPUS, f) for f in os.listdir(EVIL_CORPUS)]

    assert len(clean_files) > 0, f"No files found in {CLEAN_CORPUS}"
    assert len(evil_files) > 0, f"No files found in {EVIL_CORPUS}"

    clean_failures = []
    for f in clean_files:
        _, output = run_filter(compiled_filter, f)
        if output != "CLEAN":
            clean_failures.append(os.path.basename(f))

    evil_failures = []
    for f in evil_files:
        _, output = run_filter(compiled_filter, f)
        if output != "EVIL":
            evil_failures.append(os.path.basename(f))

    error_msgs = []
    if evil_failures:
        error_msgs.append(f"{len(evil_failures)} of {len(evil_files)} evil bypassed: " + ", ".join(evil_failures[:10]))
    if clean_failures:
        error_msgs.append(f"{len(clean_failures)} of {len(clean_files)} clean modified: " + ", ".join(clean_failures[:10]))

    if error_msgs:
        pytest.fail(" | ".join(error_msgs))

def expected_for(data):
    if len(data) < 16:
        return "CLEAN"
    magic, length, checksum, _ = struct.unpack("<IIII", data[:16])
    if magic == 0xDEADBEEF and checksum == (length ^ 0xFFFFFFFF) and length > 0x0000FFFF:
        return "EVIL"
    return "CLEAN"

def test_generated_neutral_paths(compiled_filter):
    rng = random.SystemRandom()
    cases = []

    for _ in range(32):
        length = rng.randrange(0x10000, 0x100000000)
        cases.append(struct.pack("<IIII", 0xDEADBEEF, length, length ^ 0xFFFFFFFF, rng.randrange(0x100000000)) + os.urandom(rng.randrange(0, 24)))

    for _ in range(16):
        length = rng.randrange(0, 0x10000)
        cases.append(struct.pack("<IIII", 0xDEADBEEF, length, length ^ 0xFFFFFFFF, rng.randrange(0x100000000)) + os.urandom(rng.randrange(0, 24)))

    for _ in range(12):
        length = rng.randrange(0x10000, 0x100000000)
        checksum = rng.randrange(0x100000000)
        if checksum == (length ^ 0xFFFFFFFF):
            checksum ^= 1
        cases.append(struct.pack("<IIII", 0xDEADBEEF, length, checksum, rng.randrange(0x100000000)))

    for _ in range(12):
        magic = rng.randrange(0x100000000)
        if magic == 0xDEADBEEF:
            magic ^= 1
        length = rng.randrange(0x10000, 0x100000000)
        cases.append(struct.pack("<IIII", magic, length, length ^ 0xFFFFFFFF, rng.randrange(0x100000000)))

    for _ in range(8):
        cases.append(os.urandom(rng.randrange(0, 16)))

    rng.shuffle(cases)
    failures = []
    with tempfile.TemporaryDirectory(prefix="inputs_") as directory:
        for data in cases:
            path = os.path.join(directory, secrets.token_hex(16))
            with open(path, "wb") as f:
                f.write(data)
            expected = expected_for(data)
            returncode, actual = run_filter(compiled_filter, path)
            if returncode != 0 or actual != expected:
                failures.append(f"{os.path.basename(path)}: expected {expected}, got {actual!r}, exit {returncode}")

    if failures:
        pytest.fail(f"{len(failures)} generated cases misclassified: " + " | ".join(failures[:10]))
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
