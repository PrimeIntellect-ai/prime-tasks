#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import secrets
import subprocess
import tempfile

SCRIPT_PATH = "/home/user/jsd_matrix.sh"
OUTPUT_PATH = "/home/user/jsd_output.txt"


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"The script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"The script {SCRIPT_PATH} is not executable."


def calc_jsd(p_counts, q_counts):
    p = [x + 0.01 for x in p_counts]
    q = [x + 0.01 for x in q_counts]
    sum_p = sum(p)
    sum_q = sum(q)
    p = [x / sum_p for x in p]
    q = [x / sum_q for x in q]
    m = [0.5 * (x + y) for x, y in zip(p, q)]

    kl_p = sum(x * math.log(x / y) for x, y in zip(p, m))
    kl_q = sum(x * math.log(x / y) for x, y in zip(q, m))
    return 0.5 * kl_p + 0.5 * kl_q


def expected_output(data):
    p_counts = data[0]
    result = []
    for i, q_counts in enumerate(data[1:], start=2):
        jsd = calc_jsd(p_counts, q_counts)
        status = "VALID" if jsd <= 0.1 else "INVALID"
        result.append(f"Row_{i}: {jsd:.6f} {status}")
    return result


def run_and_check(csv_path, data):
    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)

    result = subprocess.run(
        [SCRIPT_PATH, csv_path], capture_output=True, text=True, timeout=15
    )
    assert result.returncode == 0, (
        f"Script failed with return code {result.returncode} and error: {result.stderr}"
    )
    assert os.path.isfile(OUTPUT_PATH), (
        f"Output file {OUTPUT_PATH} was not created by the script."
    )

    with open(OUTPUT_PATH, "r") as f:
        output_lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_lines = expected_output(data)
    assert len(output_lines) == len(expected_lines), (
        f"Expected {len(expected_lines)} lines of output, but got {len(output_lines)}."
    )
    for i, (out_line, exp_line) in enumerate(zip(output_lines, expected_lines), start=2):
        assert out_line == exp_line, (
            f"Output mismatch at Row_{i}. Expected: '{exp_line}', Got: '{out_line}'"
        )


def test_script_logic():
    test_csv_path = "/home/user/test_grading_data.csv"
    csv_content = (
        "10,20,30,40\n"
        "10,20,30,40\n"
        "0,0,0,100\n"
        "5,25,30,40\n"
        "100,0,0,0\n"
        "0,0,0,0\n"
    )

    with open(test_csv_path, "w") as f:
        f.write(csv_content)

    lines = csv_content.strip().split("\n")
    data = [[float(x) for x in line.split(",")] for line in lines]
    run_and_check(test_csv_path, data)


def test_script_on_unpredictable_csv_inputs():
    rng = secrets.SystemRandom()

    # Vary both matrix dimensions and values so output cannot be a canned answer
    # for the public fixture. Include zeros and fractional non-negative counts.
    cases = [[[0.0], [7.25], [0.0]]]
    for _ in range(5):
        columns = rng.randint(2, 9)
        rows = rng.randint(2, 8)
        matrix = []
        for _row in range(rows):
            row = []
            for _column in range(columns):
                if rng.randrange(4) == 0:
                    value = 0.0
                else:
                    value = rng.randint(1, 50000) / rng.choice((1, 10, 100))
                row.append(value)
            matrix.append(row)
        cases.append(matrix)

    for data in cases:
        fd, csv_path = tempfile.mkstemp(prefix="jsd_case_", suffix=".csv")
        try:
            with os.fdopen(fd, "w") as f:
                for row in data:
                    f.write(",".join(format(value, ".10g") for value in row) + "\n")

            # Derive expectations from the exact decimal values written to disk.
            with open(csv_path, "r") as f:
                disk_data = [
                    [float(value) for value in line.strip().split(",")]
                    for line in f
                    if line.strip()
                ]
            run_and_check(csv_path, disk_data)
        finally:
            if os.path.exists(csv_path):
                os.remove(csv_path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
