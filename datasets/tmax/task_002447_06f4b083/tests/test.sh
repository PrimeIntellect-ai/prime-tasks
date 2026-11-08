#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import string
import subprocess
import tempfile
import pytest

VALIDATOR = "/home/user/validator"
HEX_BYTES = set(b"0123456789abcdefABCDEF")


def test_master_pin_file():
    path = "/home/user/master_pin.txt"
    assert os.path.isfile(path), f"Missing required file: {path}"
    with open(path, "r") as f:
        content = f.read().strip()
    assert content == "84920155", f"Incorrect Master PIN in {path}. Expected '84920155', got '{content}'"


def test_salt_file():
    path = "/home/user/salt.txt"
    assert os.path.isfile(path), f"Missing required file: {path}"
    with open(path, "r") as f:
        content = f.read().strip()
    assert content == "x9K2mP4vL8sQ1wE7", f"Incorrect salt in {path}. Expected 'x9K2mP4vL8sQ1wE7', got '{content}'"


def test_validator_source_exists():
    path = "/home/user/validator.c"
    assert os.path.isfile(path), f"Missing required C source file: {path}"
    assert os.path.getsize(path) > 0, f"C source file is empty: {path}"


def test_validator_executable_exists():
    path = "/home/user/validator"
    assert os.path.isfile(path), f"Missing compiled validator executable: {path}"
    assert os.access(path, os.X_OK), f"Validator executable {path} is not marked as executable"
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"Validator {path} is not a compiled ELF executable"


def test_validator_clean_corpus():
    validator_path = "/home/user/validator"
    clean_dir = "/app/corpus/clean"
    assert os.path.isdir(clean_dir), f"Clean corpus directory missing: {clean_dir}"

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]
    assert len(clean_files) > 0, f"No files found in clean corpus directory: {clean_dir}"

    failed_files = []
    for filepath in clean_files:
        result = subprocess.run([validator_path, filepath], capture_output=True)
        if result.returncode != 0:
            failed_files.append(os.path.basename(filepath))

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(clean_files)} clean tokens rejected (expected exit 0). Offending files: {', '.join(failed_files)}")


def test_validator_evil_corpus():
    validator_path = "/home/user/validator"
    evil_dir = "/app/corpus/evil"
    assert os.path.isdir(evil_dir), f"Evil corpus directory missing: {evil_dir}"

    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]
    assert len(evil_files) > 0, f"No files found in evil corpus directory: {evil_dir}"

    failed_files = []
    for filepath in evil_files:
        result = subprocess.run([validator_path, filepath], capture_output=True)
        if result.returncode == 0:
            failed_files.append(os.path.basename(filepath))

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(evil_files)} evil tokens bypassed (expected exit 1). Offending files: {', '.join(failed_files)}")


def token_is_valid(data, pin, salt):
    return (
        len(data) == 32
        and data[:4] == pin[:4]
        and data[4:20] == salt
        and all(byte in HEX_BYTES for byte in data[20:])
    )


def run_case(path, expected_status):
    try:
        result = subprocess.run([VALIDATOR, path], capture_output=True, timeout=3)
    except subprocess.TimeoutExpired:
        pytest.fail(f"Validator timed out on generated token {path}")
    assert result.returncode == expected_status, (
        f"Validator returned {result.returncode} for generated token {path}; "
        f"expected exactly {expected_status}"
    )


def test_validator_generated_and_path_independent_cases():
    with open("/home/user/master_pin.txt", "rb") as f:
        pin = f.read().strip()
    with open("/home/user/salt.txt", "rb") as f:
        salt = f.read().strip()

    assert len(pin) >= 4
    assert len(salt) == 16

    root = tempfile.mkdtemp(prefix="validator-generated-")
    misleading_clean = os.path.join(root, "clean")
    misleading_evil = os.path.join(root, "evil")
    neutral = os.path.join(root, "tokens")
    os.makedirs(misleading_clean)
    os.makedirs(misleading_evil)
    os.makedirs(neutral)

    alphabet = string.hexdigits
    valid_cases = []
    for _ in range(24):
        suffix = "".join(secrets.choice(alphabet) for _ in range(12)).encode("ascii")
        valid_cases.append(pin[:4] + salt + suffix)

    base = pin[:4] + salt + b"0123456789aB"
    invalid_cases = [
        b"",
        base[:-1],
        base + b"0",
        b"X" + base[1:],
        base[:4] + b"X" + base[5:],
        base[:20] + b"G" + base[21:],
        base[:20] + b"\x00" + base[21:],
        base[:20] + b"\xff" + base[21:],
        os.urandom(32),
        os.urandom(64),
    ]

    for i, data in enumerate(valid_cases):
        # Valid tokens deliberately live under a directory named "evil".
        path = os.path.join(misleading_evil, f"case-{i}-{secrets.token_hex(5)}.bin")
        with open(path, "wb") as f:
            f.write(data)
        expected = 0 if token_is_valid(data, pin, salt) else 1
        assert expected == 0
        run_case(path, expected)

    for i, data in enumerate(invalid_cases):
        # Invalid tokens deliberately live under a directory named "clean".
        path = os.path.join(misleading_clean, f"case-{i}-{secrets.token_hex(5)}.bin")
        with open(path, "wb") as f:
            f.write(data)
        expected = 0 if token_is_valid(data, pin, salt) else 1
        assert expected == 1
        run_case(path, expected)

    # Exercise additional unpredictable mutations at neutral paths.
    for i in range(30):
        data = bytearray(random.choice(valid_cases))
        position = secrets.randbelow(32)
        data[position] = secrets.randbelow(256)
        data = bytes(data)
        path = os.path.join(neutral, f"random-{i}-{secrets.token_hex(6)}.bin")
        with open(path, "wb") as f:
            f.write(data)
        expected = 0 if token_is_valid(data, pin, salt) else 1
        run_case(path, expected)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
