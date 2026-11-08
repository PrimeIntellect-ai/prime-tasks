#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import struct
import subprocess
import tempfile

import pytest

SOURCE_PATH = "/home/user/verify.c"
EXE_PATH = "/home/user/verify"


def test_verify_c_exists():
    """Test that the C program source file exists."""
    assert os.path.isfile(SOURCE_PATH), "The C source file /home/user/verify.c does not exist."


def test_verify_executable_exists():
    """Test that the compiled executable exists and is executable."""
    assert os.path.isfile(EXE_PATH), f"The executable {EXE_PATH} does not exist."
    assert os.access(EXE_PATH, os.X_OK), f"The file {EXE_PATH} is not executable."
    with open(EXE_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"The file {EXE_PATH} is not a compiled executable."


@pytest.fixture(scope="session")
def compiled_source(tmp_path_factory):
    """Compile the submitted C source independently so its implementation is tested."""
    output = tmp_path_factory.mktemp("compiled") / "verify_from_source"
    result = subprocess.run(
        ["gcc", "-std=c11", SOURCE_PATH, "-o", str(output)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert result.returncode == 0, (
        "The submitted verify.c could not be compiled:\n"
        + result.stderr.decode("utf-8", errors="replace")
    )
    return str(output)


def make_rle(path, blocks, expected):
    payload = b"".join(bytes((count, ord(character))) for count, character in blocks)
    with open(path, "wb") as f:
        f.write(payload)
        f.write(struct.pack("<I", expected))


def assert_status(executable, path, expected_status):
    result = subprocess.run(
        [executable, path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
    )
    expected_output = (expected_status + "\n").encode("ascii")
    assert result.stdout == expected_output, (
        f"{executable} produced {result.stdout!r} for {path}; "
        f"expected {expected_output!r}. stderr was {result.stderr!r}"
    )


def test_verifier_behavior(compiled_source, tmp_path):
    """Exercise both the submitted executable and a fresh build on derived cases."""
    cases = []

    valid_one = tmp_path / "valid one.rle"
    make_rle(valid_one, [(3, "A"), (4, "C"), (1, "T")], 8)
    cases.append((valid_one, "OK"))

    valid_large = tmp_path / "valid_large.rle"
    make_rle(valid_large, [(255, "G"), (200, "T"), (17, "A")], 472)
    cases.append((valid_large, "OK"))

    mismatch = tmp_path / "mismatch.rle"
    make_rle(mismatch, [(9, "A"), (11, "C")], 21)
    cases.append((mismatch, "CORRUPT"))

    rng = random.SystemRandom()
    for index in range(10):
        blocks = [(rng.randint(1, 255), rng.choice("ACGT")) for _ in range(rng.randint(1, 12))]
        actual = sum(count for count, _ in blocks)
        should_match = index % 2 == 0
        expected = actual if should_match else actual + rng.randint(1, 1000)
        path = tmp_path / f"generated_{index}.rle"
        make_rle(path, blocks, expected)
        cases.append((path, "OK" if should_match else "CORRUPT"))

    for length in range(4):
        path = tmp_path / f"too_short_{length}.rle"
        path.write_bytes(os.urandom(length))
        cases.append((path, "CORRUPT"))

    for executable in (EXE_PATH, compiled_source):
        for path, expected_status in cases:
            assert_status(executable, str(path), expected_status)


def test_summary_log_content():
    """Test that summary.log exists, contains the correct results, and is sorted."""
    log_path = "/home/user/summary.log"
    assert os.path.isfile(log_path), f"The log file {log_path} does not exist."

    expected_lines = [
        "/home/user/data/setA/nested/sample2.rle OK",
        "/home/user/data/setA/sample1.rle OK",
        "/home/user/data/setB/sample3.rle CORRUPT",
        "/home/user/data/setB/sample4.rle CORRUPT"
    ]

    with open(log_path, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert actual_lines == expected_lines, f"The contents of {log_path} do not match the expected sorted output."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
