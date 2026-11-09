#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import re
import subprocess

EXPECTED_HEADER = ["h", "approx", "error"]
SCI16_RE = re.compile(r"^[+-]?\d\.\d{16}e[+-]\d{2,3}$")


def validate_numerical_csv_text(text):
    rows = list(csv.reader(text.splitlines()))
    assert rows, "CSV output is empty."
    assert rows[0] == EXPECTED_HEADER, f"Incorrect CSV header: {rows[0]}"
    assert len(rows) == 17, f"Expected 1 header + 16 data rows, found {len(rows)} rows."

    for i, row in enumerate(rows[1:], start=1):
        assert len(row) == 3, f"Row {i} does not have 3 columns."
        expected_h_string = f"{10.0 ** (-i):e}"
        assert row[0] == expected_h_string, (
            f"Row {i} has h={row[0]!r}; expected {expected_h_string!r}."
        )
        assert SCI16_RE.fullmatch(row[1]), f"Row {i} approximation has incorrect formatting: {row[1]!r}"
        assert SCI16_RE.fullmatch(row[2]), f"Row {i} error has incorrect formatting: {row[2]!r}"

        h = float(row[0])
        approx = float(row[1])
        error = float(row[2])
        assert all(math.isfinite(v) for v in (h, approx, error)), f"Row {i} contains a non-finite value."

        pi = 3.14159265358979323846
        x = pi / 4.0
        expected_approx = (math.sin(x + h) - math.sin(x)) / h
        expected_error = abs(expected_approx - math.cos(x))

        assert math.isclose(approx, expected_approx, rel_tol=2e-15, abs_tol=2e-15), (
            f"Row {i} approximation is {approx:.17g}; expected {expected_approx:.17g}."
        )
        assert math.isclose(error, expected_error, rel_tol=5e-14, abs_tol=5e-18), (
            f"Row {i} error is {error:.17g}; expected {expected_error:.17g}."
        )

    expected_best_h = min(rows[1:], key=lambda row: float(row[2]))[0]
    return expected_best_h


def validate_generated_artifacts():
    with open("/home/user/results.csv", "r", newline="") as f:
        expected_best_h = validate_numerical_csv_text(f.read())

    with open("/home/user/best_h.txt", "r") as f:
        actual_best_h = f.read().strip()
    assert actual_best_h == expected_best_h, (
        f"best_h.txt ({actual_best_h}) does not match the verified minimum-error h ({expected_best_h})."
    )


def test_files_exist():
    """Check that all required files exist."""
    required_files = [
        "/home/user/finite_diff.c",
        "/home/user/pipeline.sh",
        "/home/user/results.csv",
        "/home/user/best_h.txt"
    ]
    for filepath in required_files:
        assert os.path.isfile(filepath), f"Required file {filepath} is missing."


def test_pipeline_executable():
    """Check that pipeline.sh is executable."""
    assert os.access("/home/user/pipeline.sh", os.X_OK), "/home/user/pipeline.sh is not executable."


def test_results_csv_format():
    """Check the format and content of results.csv."""
    with open("/home/user/results.csv", "r") as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) > 0, "results.csv is empty."
    assert rows[0] == ["h", "approx", "error"], f"Incorrect CSV header: {rows[0]}"
    assert len(rows) == 17, f"Expected 1 header + 16 data rows, found {len(rows)} rows."

    for i, row in enumerate(rows[1:], start=1):
        assert len(row) == 3, f"Row {i} does not have 3 columns."
        try:
            float(row[0])
            float(row[1])
            float(row[2])
        except ValueError:
            assert False, f"Row {i} contains non-numeric data: {row}"


def test_best_h_correctness():
    """Check that best_h.txt contains the h value with the minimum error from results.csv."""
    min_error = float('inf')
    best_h_from_csv = None

    with open("/home/user/results.csv", "r") as f:
        reader = csv.reader(f)
        next(reader)
        for row in reader:
            h_val = row[0]
            try:
                err_val = float(row[2])
                if err_val < min_error:
                    min_error = err_val
                    best_h_from_csv = h_val
            except ValueError:
                pass

    with open("/home/user/best_h.txt", "r") as f:
        best_h_from_file = f.read().strip()

    assert best_h_from_file == best_h_from_csv, f"best_h.txt ({best_h_from_file}) does not match the h with minimum error in results.csv ({best_h_from_csv})."


def test_c_program_computes_required_values():
    """Compile the submitted C source independently and verify its numerical output."""
    executable = "/tmp/finite_diff_under_test"
    compile_result = subprocess.run(
        ["gcc", "/home/user/finite_diff.c", "-o", executable, "-lm"],
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert compile_result.returncode == 0, f"finite_diff.c failed to compile:\n{compile_result.stderr}"

    run_result = subprocess.run([executable], capture_output=True, text=True, timeout=20)
    assert run_result.returncode == 0, f"Compiled finite_diff program failed:\n{run_result.stderr}"
    validate_numerical_csv_text(run_result.stdout)
    validate_generated_artifacts()


def test_reproducibility():
    """Run the pipeline script and verify it exits successfully and updates files."""
    os.remove("/home/user/best_h.txt")

    result = subprocess.run(["bash", "/home/user/pipeline.sh"], capture_output=True, text=True, timeout=30)
    assert result.returncode == 0, f"pipeline.sh failed with return code {result.returncode}.\nStderr: {result.stderr}"
    assert os.path.isfile("/home/user/best_h.txt"), "pipeline.sh did not recreate best_h.txt."

    assert os.path.isfile("/home/user/finite_diff"), "pipeline.sh did not create the finite_diff executable."
    assert os.access("/home/user/finite_diff", os.X_OK), "The generated finite_diff file is not executable."
    generated_run = subprocess.run(
        ["/home/user/finite_diff"], capture_output=True, text=True, timeout=20
    )
    assert generated_run.returncode == 0, f"Generated finite_diff executable failed:\n{generated_run.stderr}"
    validate_numerical_csv_text(generated_run.stdout)
    validate_generated_artifacts()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
