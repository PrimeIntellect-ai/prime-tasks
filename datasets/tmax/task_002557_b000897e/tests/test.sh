#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import tempfile

EXECUTABLE = "/home/user/calc_hash"
SOURCE = "/home/user/calc_hash.c"
FIRMWARE = "/home/user/firmware.bin"
OUTPUT = "/home/user/hash_output.txt"


def calc_expected_checksum(filepath, size):
    with open(filepath, 'rb') as f:
        data = f.read(size)
    checksum = 0
    for byte in data:
        checksum = (((checksum << 1) | (checksum >> 7)) & 0xFF)
        checksum ^= byte
    return checksum


def run_and_check(executable, filepath, expr, size):
    expected = f"{calc_expected_checksum(filepath, size)}\n"
    result = subprocess.run(
        [executable, filepath, expr],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=5,
        check=False,
    )
    assert result.returncode == 0, (
        f"{executable} failed for expression {expr!r}: {result.stderr}"
    )
    assert result.stdout == expected, (
        f"Incorrect output for expression {expr!r}: "
        f"expected {expected!r}, got {result.stdout!r}"
    )


def test_executable_exists():
    executable_path = "/home/user/calc_hash"
    assert os.path.isfile(executable_path), f"Compiled executable missing: {executable_path}"
    assert os.access(executable_path, os.X_OK), f"File is not executable: {executable_path}"
    with open(executable_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "calc_hash is not a compiled ELF executable"


def test_source_compiles_with_required_flags():
    assert os.path.isfile(SOURCE), f"C source missing: {SOURCE}"
    result = subprocess.run(
        ["gcc", "-O2", "-Wall", "-Werror", SOURCE, "-o", "/tmp/calc_hash_verified"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
        check=False,
    )
    assert result.returncode == 0, f"C source does not compile with required flags:\n{result.stderr}"


def test_hash_output_correct():
    output_file = "/home/user/hash_output.txt"
    firmware_file = "/home/user/firmware.bin"

    assert os.path.isfile(output_file), f"Output file missing: {output_file}"
    assert os.path.isfile(firmware_file), f"Firmware file missing: {firmware_file}"

    size = 512 * 7 + 13
    expected_checksum = calc_expected_checksum(firmware_file, size)
    expected_output = f"{expected_checksum}\n"

    with open(output_file, 'r') as f:
        actual_output = f.read()

    assert actual_output == expected_output, (
        f"Output in {output_file} is incorrect. "
        f"Expected '{expected_output.strip()}', got '{actual_output.strip()}'"
    )


def test_program_matches_checksum_logic_on_varied_inputs():
    assert os.path.isfile("/tmp/calc_hash_verified")

    fd, artifact = tempfile.mkstemp(prefix="hash_artifact_", dir="/tmp")
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(os.urandom(32768))

        a = secrets.randbelow(700) + 100
        b = secrets.randbelow(20) + 2
        c = secrets.randbelow(500) + 1
        cases = [
            ("1*1+1", 2),
            ("17*19+23", 17 * 19 + 23),
            ("12345*2+17", 12345 * 2 + 17),
            ("20000*3+7", 20000 * 3 + 7),
            (f"{a}*{b}+{c}", a * b + c),
        ]

        reference = "/home/user/calc_hash.py"
        hidden_reference = f"/tmp/calc_hash_reference_{secrets.token_hex(8)}"
        moved_reference = False
        if os.path.exists(reference):
            os.rename(reference, hidden_reference)
            moved_reference = True
        try:
            for executable in (EXECUTABLE, "/tmp/calc_hash_verified"):
                for expr, size in cases:
                    run_and_check(executable, artifact, expr, size)
        finally:
            if moved_reference:
                os.rename(hidden_reference, reference)
    finally:
        if os.path.exists(artifact):
            os.unlink(artifact)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
