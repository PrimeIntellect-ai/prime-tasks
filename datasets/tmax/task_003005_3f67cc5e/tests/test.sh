#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import subprocess
import tempfile
import pytest

EVIL_SIGNATURES = [
    b'\x90\x90\x90\x90',
    b'EVASION',
    b'\x00\x00\x00\x00',
]


def test_staging_key_extracted():
    """Validates that the staging key was correctly extracted from the video."""
    key_path = "/home/user/staging_key.txt"
    assert os.path.exists(key_path), f"Staging key file not found at {key_path}"

    with open(key_path, "r") as f:
        content = f.read().strip()

    expected_key = "7a4b9c2f8d1e5a6b3c9f4d7e2a1b8c5f"
    assert content == expected_key, f"Extracted key is incorrect. Expected '{expected_key}', got '{content}'"


def test_sanitizer_binary_exists_and_executable():
    """Validates that the sanitizer source exists and its binary is a native executable."""
    source_path = "/home/user/sanitizer.c"
    bin_path = "/home/user/sanitizer"

    assert os.path.isfile(source_path), f"Sanitizer C source not found at {source_path}"
    assert os.path.exists(bin_path), f"Sanitizer binary not found at {bin_path}"
    assert os.access(bin_path, os.X_OK), f"Sanitizer binary at {bin_path} is not executable"

    with open(bin_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Sanitizer is not a compiled native executable"


def test_sanitizer_against_corpora():
    """
    Validates the sanitizer against the adversarial corpus.
    Must accept all clean files (exit code 0) and reject all evil files (exit code 1).
    """
    bin_path = "/home/user/sanitizer"
    clean_dir = "/app/corpus/clean"
    evil_dir = "/app/corpus/evil"

    assert os.path.exists(bin_path), f"Sanitizer binary missing at {bin_path}"
    assert os.path.isdir(clean_dir), f"Clean corpus directory missing at {clean_dir}"
    assert os.path.isdir(evil_dir), f"Evil corpus directory missing at {evil_dir}"

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]

    assert len(clean_files) > 0, "No files found in clean corpus directory."
    assert len(evil_files) > 0, "No files found in evil corpus directory."

    clean_failures = []
    for f in clean_files:
        result = subprocess.run([bin_path, f], capture_output=True)
        if result.returncode != 0:
            clean_failures.append(os.path.basename(f))

    evil_failures = []
    for f in evil_files:
        result = subprocess.run([bin_path, f], capture_output=True)
        if result.returncode != 1:
            evil_failures.append(os.path.basename(f))

    error_messages = []
    if evil_failures:
        error_messages.append(f"{len(evil_failures)} of {len(evil_files)} evil bypassed: {', '.join(evil_failures)}")
    if clean_failures:
        error_messages.append(f"{len(clean_failures)} of {len(clean_files)} clean modified (rejected): {', '.join(clean_failures)}")

    if error_messages:
        pytest.fail(" | ".join(error_messages))


def _clean_payload(length):
    while True:
        data = os.urandom(length)
        if not any(sig in data for sig in EVIL_SIGNATURES):
            return data


def _make_dynamic_cases():
    cases = []
    for sig in EVIL_SIGNATURES:
        for _ in range(12):
            length = secrets.randbelow(961) + 64
            clean = _clean_payload(length)
            cases.append((clean, 0))

            evil = bytearray(_clean_payload(length))
            position = secrets.randbelow(length - len(sig) + 1)
            evil[position:position + len(sig)] = sig
            cases.append((bytes(evil), 1))
    random.SystemRandom().shuffle(cases)
    return cases


def _exercise_dynamic_cases(executable, directory, cases):
    failures = []
    os.makedirs(directory)
    for payload, expected in cases:
        name = secrets.token_hex(16) + ".bin"
        path = os.path.join(directory, name)
        with open(path, "wb") as f:
            f.write(payload)
        result = subprocess.run([executable, path], capture_output=True, timeout=3)
        if result.returncode != expected:
            failures.append((name, expected, result.returncode))

    assert not failures, "Dynamic payload classifications failed: " + ", ".join(
        f"{name} expected {expected}, got {actual}"
        for name, expected, actual in failures[:10]
    )


def test_sanitizer_on_unseen_payloads_and_recompiled_source():
    """Exercises both the submitted binary and a fresh build on hidden randomized paths."""
    source_path = "/home/user/sanitizer.c"
    submitted_binary = "/home/user/sanitizer"
    cases = _make_dynamic_cases()

    with tempfile.TemporaryDirectory(prefix="sanitizer_verify_") as temp_dir:
        rebuilt_binary = os.path.join(temp_dir, secrets.token_hex(12))
        build = subprocess.run(
            ["gcc", source_path, "-O2", "-o", rebuilt_binary],
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert build.returncode == 0, f"Failed to compile sanitizer.c:\n{build.stderr}"
        assert os.access(rebuilt_binary, os.X_OK), "Freshly compiled sanitizer is not executable"

        _exercise_dynamic_cases(
            submitted_binary,
            os.path.join(temp_dir, secrets.token_hex(12)),
            cases,
        )
        _exercise_dynamic_cases(
            rebuilt_binary,
            os.path.join(temp_dir, secrets.token_hex(12)),
            cases,
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
