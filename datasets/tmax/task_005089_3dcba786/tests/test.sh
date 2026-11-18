#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import random
import secrets
import subprocess
import tempfile
import uuid

import pytest

FILTER_SOURCE = "/home/user/filter.c"
FILTER_BIN = "/home/user/filter"
CLEAN_CORPUS_DIR = "/app/corpus/clean"
EVIL_CORPUS_DIR = "/app/corpus/evil"
SECRET_KEY = b"Dyn@m1cT0k3n_99!"
RESTRICTED = [b"root", b"admin", b"/proc/", b"cmdline", b"/bin/sh", b"bash"]


def run_filter(path):
    return subprocess.run(
        [FILTER_BIN, path],
        capture_output=True,
        timeout=5,
    )


def encode_payload(data, corrupt_signature=False):
    signature = bytearray(hashlib.sha256(data + SECRET_KEY).digest())
    if corrupt_signature:
        signature[secrets.randbelow(len(signature))] ^= 1 + secrets.randbelow(255)
    return (bytes(signature) + data).hex()


def test_filter_binary_exists():
    assert os.path.exists(FILTER_BIN), f"Filter binary not found at {FILTER_BIN}"
    assert os.path.isfile(FILTER_BIN), f"{FILTER_BIN} is not a file"
    assert os.access(FILTER_BIN, os.X_OK), f"{FILTER_BIN} is not executable"

    assert os.path.isfile(FILTER_SOURCE), f"C source not found at {FILTER_SOURCE}"
    with open(FILTER_BIN, "rb") as executable:
        assert executable.read(4) == b"\x7fELF", f"{FILTER_BIN} is not a compiled ELF executable"


def test_clean_corpus_accepted():
    assert os.path.isdir(CLEAN_CORPUS_DIR), f"Clean corpus directory missing: {CLEAN_CORPUS_DIR}"

    clean_files = [os.path.join(CLEAN_CORPUS_DIR, f) for f in os.listdir(CLEAN_CORPUS_DIR) if f.endswith(".txt")]
    assert len(clean_files) > 0, "No clean payload files found."

    rejected = []
    for fpath in clean_files:
        result = run_filter(fpath)
        if result.returncode != 0:
            rejected.append(os.path.basename(fpath))

    if rejected:
        pytest.fail(f"{len(rejected)} of {len(clean_files)} clean modified/rejected: {', '.join(rejected)}")


def test_evil_corpus_rejected():
    assert os.path.isdir(EVIL_CORPUS_DIR), f"Evil corpus directory missing: {EVIL_CORPUS_DIR}"

    evil_files = [os.path.join(EVIL_CORPUS_DIR, f) for f in os.listdir(EVIL_CORPUS_DIR) if f.endswith(".txt")]
    assert len(evil_files) > 0, "No evil payload files found."

    bypassed = []
    for fpath in evil_files:
        result = run_filter(fpath)
        if result.returncode == 0:
            bypassed.append(os.path.basename(fpath))

    if bypassed:
        pytest.fail(f"{len(bypassed)} of {len(evil_files)} evil bypassed: {', '.join(bypassed)}")


def test_randomized_payloads_outside_labeled_corpora():
    cases = []

    for _ in range(18):
        data = (
            b"user=" + secrets.token_hex(10).encode("ascii")
            + b";action=verify;nonce=" + secrets.token_hex(16).encode("ascii")
        )
        cases.append((encode_payload(data), 0))

    for restricted in RESTRICTED:
        for _ in range(2):
            data = (
                b"token=" + secrets.token_hex(8).encode("ascii")
                + b";value=" + restricted
                + b";nonce=" + secrets.token_hex(8).encode("ascii")
            )
            cases.append((encode_payload(data), 1))

    for _ in range(3):
        data = b"user=" + secrets.token_hex(12).encode("ascii") + b";action=verify"
        cases.append((encode_payload(data, corrupt_signature=True), 1))

    cases.extend([
        ("", 1),
        ("00" * 31, 1),
        ("00" * 32, 1),
        ("0", 1),
        ("GG" + secrets.token_hex(40), 1),
        (secrets.token_hex(40) + " ", 1),
    ])

    random.SystemRandom().shuffle(cases)

    with tempfile.TemporaryDirectory(prefix="inspection-") as temp_dir:
        failures = []
        for contents, expected_status in cases:
            path = os.path.join(temp_dir, uuid.uuid4().hex)
            with open(path, "w", encoding="ascii") as payload_file:
                payload_file.write(contents)

            result = run_filter(path)
            if result.returncode != expected_status:
                failures.append(
                    f"{os.path.basename(path)} expected {expected_status}, got {result.returncode}"
                )

        if failures:
            pytest.fail("Randomized validation failures: " + "; ".join(failures))
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
