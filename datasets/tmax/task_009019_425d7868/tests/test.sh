#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import struct
import subprocess
from pathlib import Path

import pytest

PROJECT = Path("/home/user/log_parser")
DATA = PROJECT / "data.bin"
RESULT = PROJECT / "result.txt"
CANONICAL_VALUES = [1000000000, 2000000000, -500000000, 2000000000]
CANONICAL_TOTAL = 4500000000


def write_log(values, expected_total=None, magic=b"LOG1"):
    if expected_total is None:
        expected_total = sum(values)
    records = b"".join(struct.pack("<Bi", 1, value) for value in values)
    DATA.write_bytes(magic + struct.pack("<q", expected_total) + records)


def run_program(expect_success=True):
    if RESULT.exists() or RESULT.is_symlink():
        RESULT.unlink()

    proc = subprocess.run(
        ["cargo", "run", "--quiet"],
        cwd=PROJECT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )

    if expect_success:
        assert proc.returncode == 0, (
            f"cargo run failed with status {proc.returncode}\n"
            f"stdout:\n{proc.stdout}\nstderr:\n{proc.stderr}"
        )
    else:
        assert proc.returncode != 0, "The program accepted an invalid log file"
        assert not RESULT.exists(), "The program wrote result.txt for an invalid log file"
    return proc


def assert_case(values):
    expected = sum(values)
    write_log(values, expected)
    run_program()
    assert RESULT.is_file(), "cargo run did not generate result.txt"
    assert RESULT.read_text().strip() == str(expected), (
        f"Expected result.txt to contain {expected}, but got "
        f"{RESULT.read_text().strip()!r}"
    )


@pytest.fixture(scope="session", autouse=True)
def execute_and_exercise_submission():
    assert (PROJECT / "Cargo.toml").is_file(), "Cargo.toml is missing"
    assert (PROJECT / "src" / "main.rs").is_file(), "src/main.rs is missing"

    # Exercise signed parsing, i32 boundary values, and totals outside i32 range.
    assert_case([2147483647, 2147483647, -1, -2000000000])
    assert_case([-2147483648, -1, 0, 2147483647])

    # Use verifier-generated values so a hardcoded result cannot pass.
    rng = random.SystemRandom()
    random_values = [rng.randint(-2147483648, 2147483647) for _ in range(25)]
    assert_case(random_values)

    # The required header and expected-checksum validations must remain active.
    write_log([7, -2, 11], 16, magic=b"BAD!")
    run_program(expect_success=False)

    write_log([7, -2, 11], 17)
    run_program(expect_success=False)

    # Finish by running the supplied canonical input and leave its result in place.
    assert_case(CANONICAL_VALUES)
    yield


def test_result_txt_exists():
    assert os.path.isfile("/home/user/log_parser/result.txt"), "result.txt was not generated. Did you run `cargo run` after fixing the code?"


def test_result_txt_content():
    try:
        with open("/home/user/log_parser/result.txt", "r") as f:
            content = f.read().strip()
    except FileNotFoundError:
        pytest.fail("result.txt is missing.")

    assert content == "4500000000", f"Expected result.txt to contain '4500000000', but got '{content}'."


def test_rust_code_compiles_and_runs():
    assert (PROJECT / "target" / "debug" / "log_parser").is_file(), "cargo run did not build the Rust binary"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
