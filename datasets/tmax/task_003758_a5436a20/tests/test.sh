#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import shutil
import struct
import subprocess
import tempfile
import pytest

FILTER_BIN = "/home/user/filter"
CLEAN_DIR = "/home/user/validation/clean"
EVIL_DIR = "/home/user/validation/evil"
TIMEOUT = 3
MAGIC = b'\xAB\xCD\xEF\x01\x02\x03'


def run_filter(filepath):
    return subprocess.run(
        [FILTER_BIN, filepath],
        capture_output=True,
        timeout=TIMEOUT,
    )


def test_filter_binary_exists():
    assert os.path.exists(FILTER_BIN), f"Filter binary not found at {FILTER_BIN}"
    assert os.path.isfile(FILTER_BIN), f"{FILTER_BIN} is not a file"
    assert os.access(FILTER_BIN, os.X_OK), f"{FILTER_BIN} is not executable"


def test_filter_clean_corpus():
    if not os.path.exists(FILTER_BIN) or not os.access(FILTER_BIN, os.X_OK):
        pytest.fail("Executable filter not found.")

    clean_files = [os.path.join(CLEAN_DIR, f) for f in os.listdir(CLEAN_DIR) if os.path.isfile(os.path.join(CLEAN_DIR, f))]
    assert clean_files, f"No clean files found in {CLEAN_DIR}"

    failed_files = []
    for filepath in clean_files:
        result = run_filter(filepath)
        if result.returncode != 0:
            failed_files.append(os.path.basename(filepath))

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(clean_files)} clean modified/rejected. Offending files: {', '.join(failed_files)}")


def test_filter_evil_corpus():
    if not os.path.exists(FILTER_BIN) or not os.access(FILTER_BIN, os.X_OK):
        pytest.fail("Executable filter not found.")

    evil_files = [os.path.join(EVIL_DIR, f) for f in os.listdir(EVIL_DIR) if os.path.isfile(os.path.join(EVIL_DIR, f))]
    assert evil_files, f"No evil files found in {EVIL_DIR}"

    failed_files = []
    for filepath in evil_files:
        result = run_filter(filepath)
        if result.returncode != 1:
            failed_files.append(os.path.basename(filepath))

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(evil_files)} evil bypassed. Offending files: {', '.join(failed_files)}")


def make_payload(rng):
    ascii_prefix = bytes(rng.randrange(0x20, 0x7f) for _ in range(rng.randrange(20, 100)))
    text = ''.join(rng.choice(['A', 'z', 'é', 'Ω', '中', '🙂']) for _ in range(rng.randrange(10, 50)))
    ascii_suffix = bytes(rng.randrange(0x20, 0x7f) for _ in range(rng.randrange(20, 100)))
    return ascii_prefix + text.encode('utf-8') + ascii_suffix


def test_filter_on_runtime_generated_unlabelled_files():
    if not os.path.exists(FILTER_BIN) or not os.access(FILTER_BIN, os.X_OK):
        pytest.fail("Executable filter not found.")

    rng = random.SystemRandom()
    workdir = tempfile.mkdtemp(prefix="filter-validation-")
    cases = []
    try:
        for _ in range(20):
            payload = make_payload(rng)

            valid = MAGIC + struct.pack('<I', len(payload)) + payload
            cases.append((valid, 0))

            bad_magic = bytes([MAGIC[0] ^ 0xff]) + MAGIC[1:] + struct.pack('<I', len(payload)) + payload
            cases.append((bad_magic, 1))

            wrong_length = len(payload) + rng.randrange(1, 100)
            cases.append((MAGIC + struct.pack('<I', wrong_length) + payload, 1))

            bad_payload = bytearray(payload)
            bad_payload[rng.randrange(0, 20)] = 0xff
            cases.append((MAGIC + struct.pack('<I', len(bad_payload)) + bytes(bad_payload), 1))

        cases.extend([
            (b'', 1),
            (MAGIC, 1),
            (MAGIC + b'\x00\x00\x00', 1),
        ])
        rng.shuffle(cases)

        failures = []
        for contents, expected in cases:
            filepath = os.path.join(workdir, secrets.token_hex(16))
            with open(filepath, 'wb') as f:
                f.write(contents)
            try:
                result = run_filter(filepath)
                actual = result.returncode
            except subprocess.TimeoutExpired:
                actual = 'timeout'
            if actual != expected:
                failures.append((os.path.basename(filepath), expected, actual))

        assert not failures, f"Filter misclassified runtime-generated files: {failures[:10]}"
    finally:
        shutil.rmtree(workdir, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
