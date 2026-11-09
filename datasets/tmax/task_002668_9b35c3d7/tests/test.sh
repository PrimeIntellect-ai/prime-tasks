#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import secrets
import subprocess

SCRIPT_PATH = "/home/user/process_etl.sh"
INPUT_PATH = "/home/user/incoming_data.csv"
OUTPUT_PATH = "/home/user/processed_data.csv"
INPUT_HEADER = "id,v1,v2,v3,v4"
OUTPUT_HEADER = "id,v1,v2,v3,v4,l2_norm,dot_product,is_outlier"
WEIGHTS = [0.5, -0.5, 1.0, 2.0]


def expected_output(rows):
    lines = [OUTPUT_HEADER]
    for row in rows:
        values = [float(value) if value != "" else 0.0 for value in row[1:]]
        l2_norm = math.sqrt(sum(value ** 2 for value in values))
        dot_product = sum(value * weight for value, weight in zip(values, WEIGHTS))
        is_outlier = 1 if l2_norm > 10.0000 else 0
        lines.append(
            f"{row[0]},{values[0]:.4f},{values[1]:.4f},"
            f"{values[2]:.4f},{values[3]:.4f},{l2_norm:.4f},"
            f"{dot_product:.4f},{is_outlier}"
        )
    return lines


def run_case(rows):
    with open(INPUT_PATH, "w", newline="") as input_file:
        input_file.write(INPUT_HEADER + "\n")
        for row in rows:
            input_file.write(",".join(row) + "\n")

    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)

    result = subprocess.run([SCRIPT_PATH], capture_output=True, text=True)
    assert result.returncode == 0, f"Script failed to execute. stderr: {result.stderr}"
    assert os.path.isfile(OUTPUT_PATH), f"Output file {OUTPUT_PATH} was not created."

    with open(OUTPUT_PATH, "r") as output_file:
        lines = [line.strip() for line in output_file.readlines() if line.strip()]

    expected_lines = expected_output(rows)
    assert lines, "Output file is empty."
    assert lines[0] == OUTPUT_HEADER, (
        f"Header is incorrect. Expected {OUTPUT_HEADER}, got {lines[0]}"
    )
    assert len(lines) == len(expected_lines), (
        f"Expected {len(expected_lines)} lines, but got {len(lines)}"
    )
    for index, (actual, expected) in enumerate(zip(lines, expected_lines), start=1):
        assert actual == expected, (
            f"Row {index} mismatch.\nExpected: {expected}\nActual:   {actual}"
        )


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."


def test_script_execution_and_output():
    original_rows = [
        ("1", "1.0", "2.0", "3.0", "4.0"),
        ("2", "0.0", "", "0.0", "0.0"),
        ("3", "10.0", "10.0", "10.0", "10.0"),
        ("4", "-1.0", "", "-3.0", ""),
        ("5", "", "2.5", "", "1.1"),
    ]
    run_case(original_rows)

    rng = secrets.SystemRandom()
    dynamic_rows = [
        ("norm_eq_10", "6.0", "8.0", "", ""),
        ("norm_gt_10", "6.0", "8.0", "1.0", ""),
        ("all_missing", "", "", "", ""),
        ("mixed_missing", "-3.0", "", "4.0", "2.0"),
    ]
    for _ in range(8):
        row_id = "r_" + secrets.token_hex(5)
        fields = []
        for _column in range(4):
            if rng.randrange(5) == 0:
                fields.append("")
            else:
                fields.append(f"{rng.randint(-12, 12)}.0")
        dynamic_rows.append((row_id, *fields))

    run_case(dynamic_rows)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
