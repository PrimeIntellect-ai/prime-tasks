#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import hashlib
import os
import random
import secrets
import subprocess
import tempfile
import uuid

import pytest
from cryptography.hazmat.primitives import padding
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes

EXECUTABLE = "/home/user/sanitizer"
SOURCE = "/home/user/sanitizer.cpp"
EVIL_DIR = "/app/corpus/evil"
CLEAN_DIR = "/app/corpus/clean"
KEY = b"X7k9Pq2mN4vB1cL5".ljust(32, b"\0")
IV = b"\0" * 16


def test_sanitizer_exists_and_executable():
    assert os.path.exists(EXECUTABLE), f"Sanitizer executable not found at {EXECUTABLE}"
    assert os.path.isfile(EXECUTABLE), f"Sanitizer path {EXECUTABLE} is not a file"
    assert os.access(EXECUTABLE, os.X_OK), f"Sanitizer executable at {EXECUTABLE} is not executable"
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Sanitizer must be a compiled executable"

    assert os.path.exists(SOURCE), f"C++ source not found at {SOURCE}"
    assert os.path.isfile(SOURCE), f"C++ source path {SOURCE} is not a file"


def test_adversarial_corpus():
    assert os.path.isdir(EVIL_DIR), f"Evil corpus directory missing: {EVIL_DIR}"
    assert os.path.isdir(CLEAN_DIR), f"Clean corpus directory missing: {CLEAN_DIR}"

    evil_files = [os.path.join(EVIL_DIR, f) for f in os.listdir(EVIL_DIR) if os.path.isfile(os.path.join(EVIL_DIR, f))]
    clean_files = [os.path.join(CLEAN_DIR, f) for f in os.listdir(CLEAN_DIR) if os.path.isfile(os.path.join(CLEAN_DIR, f))]

    assert len(evil_files) > 0, "No files found in evil corpus."
    assert len(clean_files) > 0, "No files found in clean corpus."

    evil_bypassed = []
    clean_modified = []

    for filepath in evil_files:
        result = subprocess.run([EXECUTABLE, filepath], capture_output=True, text=True)
        if result.returncode != 1 or "EVIL" not in result.stdout:
            evil_bypassed.append(os.path.basename(filepath))

    for filepath in clean_files:
        result = subprocess.run([EXECUTABLE, filepath], capture_output=True, text=True)
        if result.returncode != 0 or "CLEAN" not in result.stdout:
            clean_modified.append(os.path.basename(filepath))

    total_evil = len(evil_files)
    total_clean = len(clean_files)
    errors = []
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {total_evil} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        errors.append(f"{len(clean_modified)} of {total_clean} clean modified (rejected): {', '.join(clean_modified)}")
    if errors:
        pytest.fail("Adversarial corpus validation failed. " + " | ".join(errors))


def encrypt(plaintext):
    padder = padding.PKCS7(128).padder()
    padded = padder.update(plaintext) + padder.finalize()
    encryptor = Cipher(algorithms.AES(KEY), modes.CBC(IV)).encryptor()
    return encryptor.update(padded) + encryptor.finalize()


def write_metadata(directory, filename_field, payload, supplied_hash=None):
    path = os.path.join(directory, uuid.uuid4().hex + ".dat")
    digest = supplied_hash if supplied_hash is not None else hashlib.sha256(payload).hexdigest()
    with open(path, "w", encoding="utf-8") as f:
        f.write(f"FILENAME: {filename_field}\n")
        f.write(f"SHA256: {digest}\n")
        f.write(f"PAYLOAD: {base64.b64encode(payload).decode('ascii')}\n")
    return path


def assert_classification(binary, path, expected):
    result = subprocess.run([binary, path], capture_output=True, text=True, timeout=5)
    expected_code = 1 if expected == "EVIL" else 0
    assert result.returncode == expected_code, (
        f"{binary} returned {result.returncode} for a generated {expected} case; "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    assert result.stdout.strip() == expected, (
        f"{binary} printed {result.stdout!r}; expected exactly {expected!r}"
    )


def test_generated_neutral_path_cases_and_rebuilt_source():
    with tempfile.TemporaryDirectory(prefix="metadata-validation-") as directory:
        rebuilt = os.path.join(directory, uuid.uuid4().hex)
        build = subprocess.run(
            ["g++", "-std=c++17", "-O2", SOURCE, "-o", rebuilt, "-lcrypto"],
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert build.returncode == 0, f"sanitizer.cpp did not compile: {build.stderr}"
        with open(rebuilt, "rb") as f:
            assert f.read(4) == b"\x7fELF"

        cases = []

        for _ in range(5):
            payload = secrets.token_bytes(random.randint(18, 80))
            benign_name = f"report..{uuid.uuid4().hex}.bin"
            cases.append((write_metadata(directory, benign_name, payload), "CLEAN"))

        traversal_names = [
            f"../{uuid.uuid4().hex}.bin",
            f"..\\{uuid.uuid4().hex}.bin",
            f"folder/%2e%2e%2f{uuid.uuid4().hex}.bin",
            f"folder/%2E%2E%2F{uuid.uuid4().hex}.bin",
        ]
        for traversal_name in traversal_names:
            cases.append((write_metadata(directory, traversal_name, secrets.token_bytes(31)), "EVIL"))

        for _ in range(4):
            payload = secrets.token_bytes(random.randint(20, 70))
            wrong_hash = hashlib.sha256(payload + b"changed").hexdigest()
            cases.append((write_metadata(directory, f"upload-{uuid.uuid4().hex}.bin", payload, wrong_hash), "EVIL"))

        for _ in range(3):
            plaintext = secrets.token_bytes(9) + b"REDTEAM_STRIKE" + secrets.token_bytes(13)
            ciphertext = encrypt(plaintext)
            cases.append((write_metadata(directory, f"upload-{uuid.uuid4().hex}.bin", ciphertext), "EVIL"))

        for _ in range(2):
            plaintext = b"BENIGN_ENCRYPTED_CONTENT_" + uuid.uuid4().hex.encode("ascii")
            ciphertext = encrypt(plaintext)
            cases.append((write_metadata(directory, f"upload-{uuid.uuid4().hex}.bin", ciphertext), "CLEAN"))

        random.SystemRandom().shuffle(cases)
        for binary in (rebuilt, EXECUTABLE):
            for path, expected in cases:
                assert_classification(binary, path, expected)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
