#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import struct
import subprocess

import pytest


def test_validator_source_exists():
    assert os.path.isfile("/home/user/validator.c"), "The C source file /home/user/validator.c is missing."


def test_validator_executable_exists():
    assert os.path.isfile("/home/user/validator"), "The compiled executable /home/user/validator is missing."
    assert os.access("/home/user/validator", os.X_OK), "The file /home/user/validator is not executable."
    with open("/home/user/validator", "rb") as f:
        assert f.read(4) == b"\x7fELF", "/home/user/validator is not a compiled ELF executable."


def test_corrupted_files_txt():
    output_file = "/home/user/corrupted_files.txt"
    assert os.path.isfile(output_file), f"The output file {output_file} is missing."

    expected_files = [
        "/home/user/storage_pool/dir_a/corrupt_magic.bin",
        "/home/user/storage_pool/dir_b/short_payload.bak",
        "/home/user/storage_pool/dir_b/sub_c/trunc_header.dat",
        "/home/user/storage_pool/long_payload.archive"
    ]
    expected_files.sort()

    with open(output_file, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert lines == expected_files, f"The contents of {output_file} do not match the expected sorted list of corrupted files."


@pytest.fixture(scope="session")
def rebuilt_validator(tmp_path_factory):
    output = tmp_path_factory.mktemp("build") / "validator-rebuilt"
    result = subprocess.run(
        ["gcc", "-std=c11", "-O2", "/home/user/validator.c", "-o", str(output)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert result.returncode == 0, (
        "validator.c could not be compiled:\n" + result.stderr.decode(errors="replace")
    )
    assert output.read_bytes()[:4] == b"\x7fELF"
    return str(output)


@pytest.fixture(scope="session")
def generated_cases(tmp_path_factory):
    case_dir = tmp_path_factory.mktemp("binary-format-cases")
    cases = []

    def add(data, expected):
        path = case_dir / secrets.token_hex(16)
        path.write_bytes(data)
        cases.append((str(path), expected))

    # Valid files, including sizes that expose byte-order and fixed-size assumptions.
    for size in (0, 1, 2, 7, 31, 257, 4096):
        payload = os.urandom(size)
        add(b"BKUP" + struct.pack("<I", size) + payload, 0)

    # Invalid magic with otherwise valid headers and payloads.
    for size in (0, 1, 19, 257):
        payload = os.urandom(size)
        add(b"XKUP" + struct.pack("<I", size) + payload, 1)

    # Every possible truncated-header length.
    full_header = b"BKUP" + struct.pack("<I", 5)
    for length in range(8):
        add(full_header[:length], 1)

    # Payloads shorter and longer than their little-endian declarations.
    for size in (1, 2, 17, 258, 1024):
        payload = os.urandom(size)
        add(b"BKUP" + struct.pack("<I", size + 1) + payload, 1)
        add(b"BKUP" + struct.pack("<I", size - 1) + payload, 1)

    # A very large declared size must not be accepted for a small file.
    add(b"BKUP" + struct.pack("<I", 0xFFFFFFFF) + os.urandom(12), 1)

    missing = case_dir / secrets.token_hex(16)
    cases.append((str(missing), 1))
    return cases


def run_case(program, path, expected):
    try:
        result = subprocess.run(
            [program, path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=3,
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"{program} timed out while validating a test file")
    assert result.returncode == expected, (
        f"{program} returned {result.returncode} for a case that should return "
        f"{expected}: {path}"
    )


def test_installed_validator_behavior(generated_cases):
    for path, expected in generated_cases:
        run_case("/home/user/validator", path, expected)


def test_source_rebuild_behavior(rebuilt_validator, generated_cases):
    for path, expected in generated_cases:
        run_case(rebuilt_validator, path, expected)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
