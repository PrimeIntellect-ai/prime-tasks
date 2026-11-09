#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import subprocess
from decimal import Decimal


def test_error_code_txt():
    path = "/home/user/error_code.txt"
    assert os.path.exists(path), f"File {path} does not exist. Did you extract the error code?"
    assert os.path.isfile(path), f"Path {path} is not a file."

    with open(path, "r") as f:
        content = f.read().strip()

    assert content == "ERR_CODE_9X2A_MALFORMED_CSV", f"Incorrect error code found in {path}. Expected 'ERR_CODE_9X2A_MALFORMED_CSV', got '{content}'."


def test_final_sum_txt():
    path = "/home/user/final_sum.txt"
    assert os.path.exists(path), f"File {path} does not exist. Did you run the aggregator and save the output?"
    assert os.path.isfile(path), f"Path {path} is not a file."

    with open(path, "r") as f:
        content = f.read().strip()

    assert content == "10000015.09", f"Incorrect final sum found in {path}. Expected '10000015.09', got '{content}'. Did you fix the precision loss and skip malformed rows correctly?"


def test_aggregator_cpp_fixed():
    path = "/home/user/aggregator.cpp"
    assert os.path.exists(path), f"File {path} does not exist."
    assert os.path.isfile(path), f"Path {path} is not a regular file."

    with open(path, "r") as f:
        content = f.read()

    # Preserve the original precision assertions.
    assert "float total" not in content, "The precision loss bug is still present: 'float total' found in aggregator.cpp. You should use 'double' or 'long double'."
    assert "double" in content, "Expected to find 'double' in aggregator.cpp to fix the precision loss."


def test_compiled_aggregator_handles_dynamic_inputs():
    source = "/home/user/aggregator.cpp"
    data_path = "/home/user/data.csv"
    executable = "/tmp/aggregator_under_test"

    build = subprocess.run(
        ["g++", "-std=c++17", "-O2", "-o", executable, source],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert build.returncode == 0, f"aggregator.cpp did not compile:\n{build.stderr}"
    assert os.path.isfile(executable), "Compilation did not produce an executable file."
    assert os.access(executable, os.X_OK), "Compiled aggregator is not executable."

    with open(data_path, "rb") as f:
        original_data = f.read()

    try:
        # Multiple unpredictable datasets prevent a fixed-output implementation.
        for case_number in range(3):
            base = 10_000_000 + secrets.randbelow(70_000_000)
            cents_a = 1 + secrets.randbelow(89)
            cents_b = 1 + secrets.randbelow(89)
            medium_cents = 100 + secrets.randbelow(20_000)

            valid_amounts = [
                Decimal(base),
                Decimal(cents_a) / Decimal(100),
                Decimal(cents_b) / Decimal(100),
                Decimal(medium_cents) / Decimal(100),
                Decimal("-3.25"),
            ]
            expected = sum(valid_amounts, Decimal("0")).quantize(Decimal("0.01"))

            start_id = 1000 + secrets.randbelow(800000)
            small_rows = [
                f"{start_id + 1},SALE,{valid_amounts[1]:.2f}",
                f"{start_id + 2},SALE,",
                f"{start_id + 3},SALE,not_a_number",
                f"{start_id + 4},REFUND,999999.99",
                f"{start_id + 5},SALE,{valid_amounts[2]:.2f}",
                f"{start_id + 6},SALE,12.34invalid",
                f"{start_id + 7},OTHER,888.88",
                f"{start_id + 8},SALE,{valid_amounts[3]:.2f}",
                f"{start_id + 9},SALE",
                f"{start_id + 10},SALE,--7.00",
                f"{start_id + 11},SALE,{valid_amounts[4]:.2f}",
            ]
            random.SystemRandom().shuffle(small_rows)
            rows = [
                "ID,TYPE,AMOUNT",
                f"{start_id},SALE,{valid_amounts[0]:.2f}",
                *small_rows,
            ]

            with open(data_path, "w", newline="") as f:
                f.write("\n".join(rows) + "\n")

            run = subprocess.run(
                [executable],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=5,
            )
            assert run.returncode == 0, (
                f"Compiled aggregator failed on dynamic case {case_number}: "
                f"exit={run.returncode}, stderr={run.stderr!r}"
            )
            actual = run.stdout.strip()
            wanted = format(expected, ".2f")
            assert actual == wanted, (
                f"Dynamic case {case_number} produced {actual!r}; expected {wanted!r}. "
                "Malformed SALE amounts must be skipped completely and valid amounts "
                "must be accumulated without float precision loss."
            )
    finally:
        with open(data_path, "wb") as f:
            f.write(original_data)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
