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

FILTER_BIN = "/home/user/filter"
FILTER_SOURCE = "/home/user/filter.c"
EVIL_CORPUS_DIR = "/app/corpus/evil"
CLEAN_CORPUS_DIR = "/app/corpus/clean"

def test_filter_binary_exists():
    assert os.path.isfile(FILTER_BIN), f"The filter binary was not found at {FILTER_BIN}"
    assert os.access(FILTER_BIN, os.X_OK), f"The filter binary at {FILTER_BIN} is not executable"

def test_filter_against_evil_corpus():
    assert os.path.isdir(EVIL_CORPUS_DIR), f"Evil corpus directory missing: {EVIL_CORPUS_DIR}"
    evil_files = [os.path.join(EVIL_CORPUS_DIR, f) for f in os.listdir(EVIL_CORPUS_DIR) if os.path.isfile(os.path.join(EVIL_CORPUS_DIR, f))]
    assert len(evil_files) > 0, "No files found in the evil corpus directory."

    bypassed_files = []
    for filepath in evil_files:
        result = subprocess.run([FILTER_BIN, filepath], capture_output=True)
        if result.returncode != 1:
            bypassed_files.append(os.path.basename(filepath))

    if bypassed_files:
        pytest.fail(f"{len(bypassed_files)} of {len(evil_files)} evil bypassed (expected exit code 1). Offending files: {', '.join(bypassed_files)}")

def test_filter_against_clean_corpus():
    assert os.path.isdir(CLEAN_CORPUS_DIR), f"Clean corpus directory missing: {CLEAN_CORPUS_DIR}"
    clean_files = [os.path.join(CLEAN_CORPUS_DIR, f) for f in os.listdir(CLEAN_CORPUS_DIR) if os.path.isfile(os.path.join(CLEAN_CORPUS_DIR, f))]
    assert len(clean_files) > 0, "No files found in the clean corpus directory."

    modified_files = []
    for filepath in clean_files:
        result = subprocess.run([FILTER_BIN, filepath], capture_output=True)
        if result.returncode != 0:
            modified_files.append(os.path.basename(filepath))

    if modified_files:
        pytest.fail(f"{len(modified_files)} of {len(clean_files)} clean modified/rejected (expected exit code 0). Offending files: {', '.join(modified_files)}")

def expected_status(payload):
    if len(payload) < 2 or payload[:2] != b"TD":
        return 0
    pos = 2
    while pos < len(payload):
        if len(payload) - pos < 3:
            return 0
        record_type = payload[pos]
        length = int.from_bytes(payload[pos + 1:pos + 3], "big")
        pos += 3
        if len(payload) - pos < length:
            return 1 if record_type == 3 else 0
        pos += length
    return 0

def make_hidden_cases():
    rng = secrets.SystemRandom()
    cases = []

    for _ in range(48):
        prefix = bytearray(b"TD")
        for _ in range(rng.randrange(0, 5)):
            record_type = rng.choice((1, 2, 3, 4, 9, 255))
            length = rng.randrange(0, 96)
            prefix += struct.pack(">BH", record_type, length)
            prefix += secrets.token_bytes(length)

        declared = rng.randrange(1, 512)
        present = rng.randrange(0, declared)
        body = secrets.token_bytes(present)
        cases.append(bytes(prefix) + struct.pack(">BH", 3, declared) + body)
        cases.append(bytes(prefix) + struct.pack(">BH", rng.choice((1, 2, 4, 9, 255)), declared) + body)

    for _ in range(20):
        prefix = bytearray(b"TD")
        for _ in range(rng.randrange(1, 5)):
            record_type = rng.choice((1, 2, 3, 4, 255))
            length = rng.randrange(0, 128)
            prefix += struct.pack(">BH", record_type, length)
            prefix += secrets.token_bytes(length)
        cases.append(bytes(prefix))

    cases.extend([
        b"",
        b"T",
        b"TX" + secrets.token_bytes(20),
        b"TD\x03",
        b"TD\x03\x00",
        b"TD\x03\x00\x00",
        b"TD\x03\x00\x01",
        b"TD\x01\x00\x01",
    ])
    rng.shuffle(cases)
    return cases

def run_hidden_cases(executable, cases):
    with tempfile.TemporaryDirectory(prefix="payload-check-") as directory:
        payload_path = os.path.join(directory, secrets.token_hex(12))
        for index, payload in enumerate(cases):
            with open(payload_path, "wb") as stream:
                stream.write(payload)
            expected = expected_status(payload)
            try:
                result = subprocess.run(
                    [executable, payload_path],
                    stdin=subprocess.DEVNULL,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    timeout=3,
                )
            except subprocess.TimeoutExpired:
                pytest.fail(f"Filter timed out on hidden payload {index}")
            assert result.returncode == expected, (
                f"Filter returned {result.returncode} on hidden payload {index}; "
                f"expected {expected}"
            )

def test_filter_on_content_derived_hidden_inputs(tmp_path):
    assert os.path.isfile(FILTER_SOURCE), f"The C source was not found at {FILTER_SOURCE}"
    with open(FILTER_BIN, "rb") as stream:
        assert stream.read(4) == b"\x7fELF", "The submitted filter is not a compiled ELF executable"

    rebuilt = tmp_path / "filter-rebuilt"
    compile_result = subprocess.run(
        ["gcc", FILTER_SOURCE, "-o", str(rebuilt)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert compile_result.returncode == 0, (
        "filter.c could not be compiled: " + compile_result.stderr.decode(errors="replace")
    )

    cases = make_hidden_cases()
    run_hidden_cases(FILTER_BIN, cases)
    run_hidden_cases(str(rebuilt), cases)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
