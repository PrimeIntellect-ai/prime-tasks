#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import shutil
import struct
import subprocess
import tempfile
import uuid

import pytest

EVIL_DIR = "/app/corpus/evil/"
CLEAN_DIR = "/app/corpus/clean/"
SANITISER_BIN = "/home/user/sanitiser"
SANITISER_SRC = "/home/user/sanitiser.cpp"

@pytest.fixture(scope="session", autouse=True)
def ensure_sanitiser():
    if not os.path.exists(SANITISER_BIN):
        assert os.path.exists(SANITISER_SRC), f"Sanitiser source not found at {SANITISER_SRC} and binary not found at {SANITISER_BIN}"
        compile_proc = subprocess.run(
            ["g++", "-O2", SANITISER_SRC, "-o", SANITISER_BIN],
            capture_output=True,
            text=True
        )
        assert compile_proc.returncode == 0, f"Failed to compile {SANITISER_SRC}:\n{compile_proc.stderr}"
    assert os.path.isfile(SANITISER_BIN), f"Sanitiser at {SANITISER_BIN} is not a regular file"
    assert os.access(SANITISER_BIN, os.X_OK), f"Sanitiser binary at {SANITISER_BIN} is not executable"

def run_sanitiser(path):
    try:
        return subprocess.run(
            [SANITISER_BIN, path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=2
        ).returncode
    except subprocess.TimeoutExpired:
        pytest.fail(f"Sanitiser timed out while checking {path}")

def test_clean_corpus_accepted():
    clean_files = [f for f in os.listdir(CLEAN_DIR) if os.path.isfile(os.path.join(CLEAN_DIR, f))]
    assert clean_files, f"Clean corpus directory is empty: {CLEAN_DIR}"

    failed_files = []
    for filename in clean_files:
        filepath = os.path.join(CLEAN_DIR, filename)
        if run_sanitiser(filepath) != 0:
            failed_files.append(filename)

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(clean_files)} clean files were incorrectly rejected (exit code != 0): {', '.join(failed_files)}")

def test_evil_corpus_rejected():
    evil_files = [f for f in os.listdir(EVIL_DIR) if os.path.isfile(os.path.join(EVIL_DIR, f))]
    assert evil_files, f"Evil corpus directory is empty: {EVIL_DIR}"

    failed_files = []
    for filename in evil_files:
        filepath = os.path.join(EVIL_DIR, filename)
        if run_sanitiser(filepath) == 0:
            failed_files.append(filename)

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(evil_files)} evil files bypassed the sanitiser (exit code == 0): {', '.join(failed_files)}")

def checksum(payload):
    return (sum(payload) * 31) & 0xffffffff

def frame(payload, magic=b"TLVM", stored_checksum=None):
    if stored_checksum is None:
        stored_checksum = checksum(payload)
    return magic + struct.pack("<I", stored_checksum) + payload

def record(record_type, value):
    return struct.pack("<BH", record_type, len(value)) + value

def safe_model(data):
    if len(data) < 8 or data[:4] != b"TLVM":
        return False
    stored = struct.unpack("<I", data[4:8])[0]
    payload = data[8:]
    if stored != checksum(payload):
        return False
    pos = 0
    while pos < len(payload):
        if pos + 3 > len(payload):
            return False
        record_type = payload[pos]
        length = struct.unpack("<H", payload[pos + 1:pos + 3])[0]
        if record_type == 0xff or length == 0:
            return False
        if pos + 3 + length > len(payload):
            return False
        pos += 3 + length
    return True

def random_valid_file():
    payload = bytearray()
    for _ in range(secrets.randbelow(8) + 1):
        record_type = secrets.randbelow(255)
        length = secrets.randbelow(1024) + 1
        payload.extend(record(record_type, secrets.token_bytes(length)))
    return frame(bytes(payload))

def test_generated_hidden_cases():
    root = tempfile.mkdtemp(prefix="telemetry-check-")
    try:
        cases = []

        # Valid files, including an empty payload and varied binary records.
        cases.append(frame(b""))
        for _ in range(30):
            cases.append(random_valid_file())
        cases.append(frame(record(0, b"x") + record(254, secrets.token_bytes(4096))))

        # Invalid headers and checksums.
        for _ in range(8):
            valid = random_valid_file()
            bad_magic = secrets.token_bytes(4)
            while bad_magic == b"TLVM":
                bad_magic = secrets.token_bytes(4)
            cases.append(bad_magic + valid[4:])
            stored = struct.unpack("<I", valid[4:8])[0]
            delta = secrets.randbelow(0xffffffff) + 1
            cases.append(valid[:4] + struct.pack("<I", (stored + delta) & 0xffffffff) + valid[8:])

        # Dangerous record types and zero-length records at varied positions.
        for _ in range(10):
            prefix = record(secrets.randbelow(255), secrets.token_bytes(secrets.randbelow(40) + 1))
            suffix = record(secrets.randbelow(255), secrets.token_bytes(secrets.randbelow(40) + 1))
            cases.append(frame(prefix + struct.pack("<BH", 0xff, secrets.randbelow(32) + 1) + secrets.token_bytes(secrets.randbelow(32) + 1)))
            cases.append(frame(prefix + struct.pack("<BH", secrets.randbelow(255), 0) + suffix))

        # Length overruns and incomplete trailing TLV headers, all with correct checksums.
        for _ in range(12):
            prefix = record(secrets.randbelow(255), secrets.token_bytes(secrets.randbelow(50) + 1))
            actual = secrets.randbelow(20)
            claimed = actual + secrets.randbelow(200) + 1
            tail = struct.pack("<BH", secrets.randbelow(255), claimed) + secrets.token_bytes(actual)
            cases.append(frame(prefix + tail))
        for tail_size in (1, 2):
            for _ in range(6):
                prefix = record(secrets.randbelow(255), secrets.token_bytes(secrets.randbelow(50) + 1))
                cases.append(frame(prefix + secrets.token_bytes(tail_size)))

        # Files too short to contain the complete header and checksum.
        for size in range(8):
            cases.append(secrets.token_bytes(size))

        secrets.SystemRandom().shuffle(cases)
        failures = []
        for data in cases:
            expected = 0 if safe_model(data) else 1
            path = os.path.join(root, uuid.uuid4().hex)
            with open(path, "wb") as output:
                output.write(data)
            actual = run_sanitiser(path)
            if actual != expected:
                failures.append((os.path.basename(path), expected, actual, len(data)))

        assert not failures, f"Generated telemetry cases misclassified: {failures[:10]}"
    finally:
        shutil.rmtree(root, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
