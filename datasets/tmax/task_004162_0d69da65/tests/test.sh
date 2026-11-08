#!/bin/bash
set -e
mkdir -p /logs/verifier
rm -f /home/user/results.log

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import subprocess

SOURCE = "/home/user/validate_model.c"
EXECUTABLE = "/home/user/validate_model"
RESULTS = "/home/user/results.log"
GOLDEN = "/tests/.golden_results"
EMBEDDINGS = "/home/user/embeddings.csv"
REFERENCE = "/home/user/reference.csv"


def run_program():
    if os.path.exists(RESULTS):
        os.remove(RESULTS)
    completed = subprocess.run(
        [EXECUTABLE],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert completed.returncode == 0, (
        f"validate_model exited with {completed.returncode}\n"
        f"stdout: {completed.stdout}\n"
        f"stderr: {completed.stderr}"
    )
    assert os.path.isfile(RESULTS), "Executable did not create /home/user/results.log"


def read_nonempty_lines(path):
    with open(path, "r") as f:
        return [line.strip() for line in f.readlines() if line.strip()]


def assert_log(expected_first_five):
    log_lines = read_nonempty_lines(RESULTS)
    assert len(log_lines) == 6, (
        f"Expected exactly 6 non-empty lines in {RESULTS}, found {len(log_lines)}"
    )
    for i in range(5):
        assert log_lines[i] == expected_first_five[i], (
            f"Line {i+1} mismatch.\n"
            f"Expected: '{expected_first_five[i]}'\n"
            f"Got:      '{log_lines[i]}'"
        )
    pattern = r"^Compute Time: \d+\.\d{6} seconds$"
    assert re.match(pattern, log_lines[5]), (
        "Line 6 does not match the required format.\n"
        "Expected format: 'Compute Time: [float.6f] seconds'\n"
        f"Got: '{log_lines[5]}'"
    )


def expected_lines(reference, valid_rows):
    dots = [sum(x * y for x, y in zip(row, reference)) for row in valid_rows]
    n = len(dots)
    mean = sum(dots) / n
    std = math.sqrt(sum((x - mean) ** 2 for x in dots) / (n - 1))
    margin = 1.96 * std / math.sqrt(n)
    return [
        f"Valid Rows: {n}",
        f"Mean Dot Product: {mean:.4f}",
        f"95% CI Lower: {mean - margin:.4f}",
        f"95% CI Upper: {mean + margin:.4f}",
        f"Status: {'VALID' if mean > 25.0 else 'INVALID'}",
    ]


def write_case(reference, valid_rows):
    with open(REFERENCE, "w") as f:
        f.write(",".join(str(x) for x in reference) + "\n")

    rows = [",".join(str(x) for x in row) for row in valid_rows]
    rows.extend([
        ",".join("0.5" for _ in range(99)),
        ",".join("0.5" for _ in range(101)),
        ",".join(["0.5"] * 50 + ["corrupted_string"] + ["0.5"] * 49),
    ])
    with open(EMBEDDINGS, "w") as f:
        for row in rows:
            f.write(row + "\n")


def test_c_source_exists():
    assert os.path.exists(SOURCE), f"Missing C source file: {SOURCE}"
    assert os.path.isfile(SOURCE), f"Not a file: {SOURCE}"


def test_executable_exists():
    assert os.path.exists(EXECUTABLE), f"Missing executable: {EXECUTABLE}"
    assert os.path.isfile(EXECUTABLE), f"Not a file: {EXECUTABLE}"
    assert os.access(EXECUTABLE, os.X_OK), f"File is not executable: {EXECUTABLE}"
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "validate_model is not a compiled ELF executable"


def test_executable_runs_on_original_data():
    run_program()


def test_results_log_exists():
    assert os.path.exists(RESULTS), f"Missing results log file: {RESULTS}"
    assert os.path.isfile(RESULTS), f"Not a file: {RESULTS}"


def test_results_log_contents():
    assert os.path.exists(RESULTS), f"Missing file: {RESULTS}"
    assert os.path.exists(GOLDEN), f"Missing verifier oracle: {GOLDEN}"
    golden_lines = read_nonempty_lines(GOLDEN)
    assert len(golden_lines) >= 5, "Golden result is incomplete"
    assert_log(golden_lines[:5])


def test_computation_and_schema_enforcement():
    with open(EMBEDDINGS, "rb") as f:
        original_embeddings = f.read()
    with open(REFERENCE, "rb") as f:
        original_reference = f.read()

    cases = [
        ([1.0] * 100, [[0.30] * 100, [0.40] * 100, [0.50] * 100, [0.60] * 100]),
        ([0.5] * 100, [[0.10] * 100, [0.20] * 100, [0.30] * 100, [0.40] * 100]),
    ]

    try:
        for reference, rows in cases:
            write_case(reference, rows)
            run_program()
            assert_log(expected_lines(reference, rows))
    finally:
        with open(EMBEDDINGS, "wb") as f:
            f.write(original_embeddings)
        with open(REFERENCE, "wb") as f:
            f.write(original_reference)
        try:
            run_program()
        except Exception:
            pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
