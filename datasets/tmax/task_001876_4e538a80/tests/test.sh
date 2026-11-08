#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import os
import secrets
import struct
import subprocess
import tempfile
import pytest

FILTER_SCRIPT = "/home/user/filter.py"
CLEAN_CORPUS_DIR = "/app/corpus/clean/"
EVIL_CORPUS_DIR = "/app/corpus/evil/"


def run_filter(path):
    return subprocess.run(
        ["python3", FILTER_SCRIPT, path],
        capture_output=True,
        timeout=5,
    )


def crc16(data):
    crc = 0x0000
    for byte in data:
        crc ^= byte << 8
        for _ in range(8):
            if crc & 0x8000:
                crc = ((crc << 1) ^ 0x1021) & 0xFFFF
            else:
                crc = (crc << 1) & 0xFFFF
    return crc ^ 0x0000


def encode_asset(data, declared_length=None, checksum=None):
    if checksum is None:
        checksum = crc16(data)
    payload = data + struct.pack("<H", checksum)
    if declared_length is None:
        declared_length = len(payload)
    decoded = struct.pack("<I", declared_length) + payload
    return base64.b64encode(decoded)


def test_filter_script_exists():
    assert os.path.exists(FILTER_SCRIPT), f"Filter script not found at {FILTER_SCRIPT}"
    assert os.path.isfile(FILTER_SCRIPT), f"Path is not a file: {FILTER_SCRIPT}"


def test_clean_corpus_accepted():
    assert os.path.exists(CLEAN_CORPUS_DIR), f"Clean corpus directory missing: {CLEAN_CORPUS_DIR}"

    clean_files = [os.path.join(CLEAN_CORPUS_DIR, f) for f in os.listdir(CLEAN_CORPUS_DIR) if os.path.isfile(os.path.join(CLEAN_CORPUS_DIR, f))]
    assert len(clean_files) > 0, "Clean corpus is empty"

    rejected_files = []
    for file_path in clean_files:
        result = run_filter(file_path)
        if result.returncode != 0:
            rejected_files.append(os.path.basename(file_path))

    if rejected_files:
        pytest.fail(f"{len(rejected_files)} of {len(clean_files)} clean rejected: {', '.join(rejected_files)}")


def test_evil_corpus_rejected():
    assert os.path.exists(EVIL_CORPUS_DIR), f"Evil corpus directory missing: {EVIL_CORPUS_DIR}"

    evil_files = [os.path.join(EVIL_CORPUS_DIR, f) for f in os.listdir(EVIL_CORPUS_DIR) if os.path.isfile(os.path.join(EVIL_CORPUS_DIR, f))]
    assert len(evil_files) > 0, "Evil corpus is empty"

    bypassed_files = []
    for file_path in evil_files:
        result = run_filter(file_path)
        if result.returncode == 0:
            bypassed_files.append(os.path.basename(file_path))

    if bypassed_files:
        pytest.fail(f"{len(bypassed_files)} of {len(evil_files)} evil bypassed: {', '.join(bypassed_files)}")


def test_generated_unlabelled_assets():
    cases = []

    # Valid assets with unpredictable contents and varied payload lengths.
    for index, size in enumerate([0, 1, 2, 3, 7, 16, 31, 64, 257]):
        encoded = encode_asset(secrets.token_bytes(size))
        if index % 3 == 1:
            encoded += b"\n"
        elif index % 3 == 2:
            encoded += b"\n\n"
        cases.append((encoded, True))

    sample = secrets.token_bytes(29)
    correct_crc = crc16(sample)
    correct_length = len(sample) + 2

    # Well-formed Base64 whose decoded length header or CRC is wrong.
    cases.extend([
        (encode_asset(sample, declared_length=correct_length + 1), False),
        (encode_asset(sample, declared_length=correct_length - 1), False),
        (encode_asset(sample, checksum=correct_crc ^ 0x0001), False),
        (encode_asset(sample, checksum=correct_crc ^ 0x8000), False),
        (base64.b64encode(struct.pack("<I", 0)), False),
        (base64.b64encode(struct.pack("<I", 1) + b"x"), False),
        (base64.b64encode(b"\x00\x01\x02"), False),
        (base64.b64encode(struct.pack("<I", 0xFFFFFFFF)), False),
    ])

    valid_text = encode_asset(secrets.token_bytes(23))
    split = max(1, len(valid_text) // 2)
    padded = encode_asset(b"x")
    assert padded.endswith(b"=")

    # Encoding violations, including whitespace that is not trailing newlines.
    cases.extend([
        (b"not base64!!!", False),
        (valid_text[:split] + b" " + valid_text[split:], False),
        (b"\n" + valid_text, False),
        (valid_text + b"\nX", False),
        (valid_text + b"#", False),
        (padded.rstrip(b"="), False),
        (b"", False),
        (b"%%%%", False),
    ])

    # Add more independently generated length and checksum failures so results
    # cannot be inferred from the shipped corpus or fixed filenames.
    for _ in range(8):
        data = secrets.token_bytes(5 + secrets.randbelow(96))
        if secrets.randbelow(2):
            cases.append((encode_asset(data, declared_length=len(data) + 3), False))
        else:
            cases.append((encode_asset(data, checksum=crc16(data) ^ (1 << secrets.randbelow(16))), False))

    with tempfile.TemporaryDirectory(prefix="asset_checks_") as directory:
        order = list(range(len(cases)))
        secrets.SystemRandom().shuffle(order)
        failures = []
        for case_number in order:
            contents, should_accept = cases[case_number]
            path = os.path.join(directory, secrets.token_hex(12) + ".dat")
            with open(path, "wb") as handle:
                handle.write(contents)
            accepted = run_filter(path).returncode == 0
            if accepted != should_accept:
                failures.append((case_number, should_accept, accepted))

        assert not failures, f"Generated asset validation failures: {failures}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
