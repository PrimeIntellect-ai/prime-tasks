#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import secrets
import subprocess
from decimal import Decimal

import pytest


def test_etl_script_exists_and_executable():
    script_path = "/home/user/etl.sh"
    assert os.path.isfile(script_path), f"Missing file: {script_path}"
    assert os.access(script_path, os.X_OK), f"File {script_path} is not executable."


def test_etl_script_reads_weights():
    script_path = "/home/user/etl.sh"
    with open(script_path, "r") as f:
        content = f.read()
    assert "weights.txt" in content, "The script does not appear to read from weights.txt dynamically."


def test_etl_execution_and_output():
    script_path = "/home/user/etl.sh"
    output_path = "/home/user/output.csv"

    # Remove output if it exists to ensure we are testing the script's execution
    if os.path.exists(output_path):
        os.remove(output_path)

    # Run the script
    result = subprocess.run([script_path], capture_output=True, text=True)
    assert result.returncode == 0, f"Script failed to execute. stderr: {result.stderr}"

    assert os.path.isfile(output_path), f"Script did not create {output_path}"

    with open(output_path, "r") as f:
        content = f.read().strip()

    expected_content = """id,score
1,115
2,50
3,-18
4,0
5,16
6,0
7,-32
8,6
9,51
10,-19"""

    assert content == expected_content, f"Output CSV does not match expected values. Got:\n{content}"


def test_etl_varied_inputs_and_dynamic_weights():
    script_path = "/home/user/etl.sh"
    data_path = "/home/user/data.csv"
    weights_path = "/home/user/weights.txt"
    output_path = "/home/user/output.csv"

    with open(data_path, "rb") as f:
        original_data = f.read()
    with open(weights_path, "rb") as f:
        original_weights = f.read()
    original_output = None
    if os.path.exists(output_path):
        with open(output_path, "rb") as f:
            original_output = f.read()

    try:
        # Quarter-valued, nonzero weights are exactly representable, avoiding
        # ambiguity at integer truncation boundaries while varying every run.
        numerators = [-15, -13, -11, -9, -7, -5, -3, -1,
                       1, 3, 5, 7, 9, 11, 13, 15]

        for trial in range(3):
            weights = [Decimal(secrets.choice(numerators)) / Decimal(4) for _ in range(3)]
            base = secrets.randbelow(800000) + 100000 + trial * 1000000
            values = [secrets.randbelow(19) + 2 for _ in range(9)]
            rows = [
                (base + 1, [str(values[0]), "", ""]),
                (base + 2, ["", str(values[1]), ""]),
                (base + 3, ["", "", str(values[2])]),
                (base + 4, [str(values[3]), str(-values[4]), str(values[5])]),
                (base + 5, [str(-values[6]), str(values[7]), str(-values[8])]),
                (base + 6, ["", "", ""]),
            ]

            with open(weights_path, "w", newline="") as f:
                for weight in weights:
                    f.write(f"{weight}\n")

            with open(data_path, "w", newline="") as f:
                f.write("id,f1,f2,f3\n")
                for record_id, features in rows:
                    f.write(str(record_id) + "," + ",".join(features) + "\n")

            expected_lines = ["id,score"]
            for record_id, features in rows:
                score = sum(
                    (Decimal(value) if value != "" else Decimal(0)) * weight
                    for value, weight in zip(features, weights)
                )
                expected_lines.append(f"{record_id},{int(score)}")
            expected = "\n".join(expected_lines)

            if os.path.exists(output_path):
                os.remove(output_path)
            result = subprocess.run(
                [script_path], capture_output=True, text=True, timeout=10
            )
            assert result.returncode == 0, (
                f"Script failed on varied input {trial}: {result.stderr}"
            )
            assert os.path.isfile(output_path), (
                f"Script did not create {output_path} on varied input {trial}"
            )
            with open(output_path, "r") as f:
                actual = f.read().strip()
            assert actual == expected, (
                f"Output was not computed from varied data/weights on trial {trial}. "
                f"Expected:\n{expected}\nGot:\n{actual}"
            )
    finally:
        with open(data_path, "wb") as f:
            f.write(original_data)
        with open(weights_path, "wb") as f:
            f.write(original_weights)
        if original_output is None:
            if os.path.exists(output_path):
                os.remove(output_path)
        else:
            with open(output_path, "wb") as f:
                f.write(original_output)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
