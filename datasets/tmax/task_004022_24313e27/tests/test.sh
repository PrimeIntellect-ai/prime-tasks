#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import struct
import subprocess
import tempfile
import time
import pytest

FAST_FILTER_PATH = "/home/user/fast_filter.sh"
CLEAN_CORPUS_DIR = "/home/user/corpus/clean/"
EVIL_CORPUS_DIR = "/home/user/corpus/evil/"
INCOMING_DIR = "/home/user/incoming/"
LOG_FILE = "/home/user/clean_backups.log"


def is_valid_bkp(filepath):
    try:
        with open(filepath, 'rb') as f:
            magic = f.read(4)
            if magic != b'BKP\x00':
                return False
            length_bytes = f.read(4)
            if len(length_bytes) != 4:
                return False
            L = struct.unpack('>I', length_bytes)[0]
            if L > 100000000:
                return False
            metadata = f.read(L)
            if len(metadata) != L:
                return False
            if b'MALWARE' in metadata:
                return False
            for byte in metadata:
                if byte < 0x20 or byte > 0x7E:
                    return False
            return True
    except Exception:
        return False


def run_filter(path):
    try:
        return subprocess.run(
            [FAST_FILTER_PATH, path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=2,
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"Filter timed out on generated input {path!r}")


def test_fast_filter_exists_and_executable():
    assert os.path.exists(FAST_FILTER_PATH), f"Filter script not found at {FAST_FILTER_PATH}"
    assert os.path.isfile(FAST_FILTER_PATH), f"{FAST_FILTER_PATH} is not a file"
    assert os.access(FAST_FILTER_PATH, os.X_OK), f"{FAST_FILTER_PATH} is not executable"


def test_fast_filter_adversarial_corpus():
    clean_files = [os.path.join(CLEAN_CORPUS_DIR, f) for f in os.listdir(CLEAN_CORPUS_DIR) if os.path.isfile(os.path.join(CLEAN_CORPUS_DIR, f))]
    evil_files = [os.path.join(EVIL_CORPUS_DIR, f) for f in os.listdir(EVIL_CORPUS_DIR) if os.path.isfile(os.path.join(EVIL_CORPUS_DIR, f))]

    clean_failed = []
    evil_bypassed = []

    for cf in clean_files:
        res = subprocess.run([FAST_FILTER_PATH, cf], capture_output=True)
        if res.returncode != 0:
            clean_failed.append(os.path.basename(cf))

    for ef in evil_files:
        res = subprocess.run([FAST_FILTER_PATH, ef], capture_output=True)
        if res.returncode == 0:
            evil_bypassed.append(os.path.basename(ef))

    errors = []
    if clean_failed:
        errors.append(f"{len(clean_failed)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_failed)}")
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")

    assert not errors, "Adversarial corpus checks failed:\n" + "\n".join(errors)


def test_fast_filter_generated_holdout():
    rng = secrets.SystemRandom()
    holdout = tempfile.mkdtemp(prefix=secrets.token_hex(12) + "-")
    cases = []

    def add_case(blob, suffix):
        name = secrets.token_hex(10) + suffix
        path = os.path.join(holdout, name)
        with open(path, 'wb') as f:
            f.write(blob)
        cases.append(path)

    # Explicit boundary and truncation cases.
    add_case(b'', '.bkp')
    add_case(b'B', '.bkp')
    add_case(b'BKP\x00', '.bkp')
    add_case(b'BKP\x00\x00\x00\x00', '.bkp')
    add_case(b'BKP\x00' + struct.pack('>I', 100000001), '.bkp')
    add_case(b'BKP\x00' + struct.pack('>I', 0), '.dat')
    add_case(b'BKP\x00' + struct.pack('>I', 5) + b'hello' + b'\x00MALWARE\xff', '.bkp')
    add_case(b'BKP\x00' + struct.pack('>I', 7) + b'MALWARE', '.bin')
    add_case(b'BKP\x00' + struct.pack('>I', 8) + b'xMALWARE', '.bkp')

    # Unpredictable valid files with varying metadata and ignored trailing data.
    for _ in range(28):
        length = rng.randrange(0, 513)
        metadata = bytes(rng.randrange(0x20, 0x7f) for _ in range(length))
        metadata = metadata.replace(b'MALWARE', b'SAFE___')
        trailing = secrets.token_bytes(rng.randrange(0, 40))
        blob = b'BKP\x00' + struct.pack('>I', len(metadata)) + metadata + trailing
        add_case(blob, rng.choice(['.bkp', '.archive', ' with spaces']))

    # Unpredictable malformed files covering every validation stage.
    for i in range(40):
        mode = i % 5
        if mode == 0:
            magic = bytearray(b'BKP\x00')
            pos = rng.randrange(4)
            magic[pos] ^= rng.randrange(1, 256)
            metadata = b'clean metadata'
            blob = bytes(magic) + struct.pack('>I', len(metadata)) + metadata
        elif mode == 1:
            metadata = secrets.token_bytes(rng.randrange(0, 25))
            declared = len(metadata) + rng.randrange(1, 30)
            blob = b'BKP\x00' + struct.pack('>I', declared) + metadata
        elif mode == 2:
            prefix = bytes(rng.randrange(0x20, 0x7f) for _ in range(rng.randrange(0, 30)))
            suffix = bytes(rng.randrange(0x20, 0x7f) for _ in range(rng.randrange(0, 30)))
            metadata = prefix + b'MALWARE' + suffix
            blob = b'BKP\x00' + struct.pack('>I', len(metadata)) + metadata
        elif mode == 3:
            metadata = bytearray(bytes(rng.randrange(0x20, 0x7f) for _ in range(rng.randrange(1, 50))))
            metadata[rng.randrange(len(metadata))] = rng.choice(list(range(0x20)) + list(range(0x7f, 0x100)))
            blob = b'BKP\x00' + struct.pack('>I', len(metadata)) + bytes(metadata)
        else:
            header_bytes = secrets.token_bytes(rng.randrange(0, 4))
            blob = b'BKP\x00' + header_bytes
        add_case(blob, rng.choice(['.bkp', '.tmp', ' no-extension']))

    failures = []
    for path in cases:
        expected = 0 if is_valid_bkp(path) else 1
        result = run_filter(path)
        if result.returncode != expected:
            failures.append(
                f"{os.path.basename(path)!r}: expected exit {expected}, got {result.returncode}"
            )

    missing = os.path.join(holdout, secrets.token_hex(10) + '.bkp')
    missing_result = run_filter(missing)
    if missing_result.returncode != 1:
        failures.append(f"missing input: expected exit 1, got {missing_result.returncode}")

    directory_result = run_filter(holdout)
    if directory_result.returncode != 1:
        failures.append(f"directory input: expected exit 1, got {directory_result.returncode}")

    assert not failures, "Generated holdout checks failed:\n" + "\n".join(failures[:20])


def test_clean_backups_log():
    assert os.path.exists(LOG_FILE), f"Log file not found at {LOG_FILE}"

    expected_files = []
    now = time.time()
    seven_days_seconds = 7 * 24 * 3600

    for root, _, files in os.walk(INCOMING_DIR):
        for f in files:
            filepath = os.path.join(root, f)
            try:
                mtime = os.path.getmtime(filepath)
                if (now - mtime) <= seven_days_seconds:
                    if is_valid_bkp(filepath):
                        expected_files.append(filepath)
            except Exception:
                pass

    expected_files.sort()

    with open(LOG_FILE, 'r') as f:
        actual_files = [line.strip() for line in f if line.strip()]

    assert actual_files == expected_files, "The contents of clean_backups.log do not match the expected valid files modified within the last 7 days."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
