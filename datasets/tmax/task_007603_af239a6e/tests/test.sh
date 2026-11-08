#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import re
import subprocess

import pytest

SOURCE = "/home/user/etl_pipeline.c"
BINARY = "/home/user/etl_pipeline"
REPORT = "/home/user/report.txt"


def run_program(program, cwd):
    result = subprocess.run(
        [program], cwd=cwd, text=True, capture_output=True, timeout=30
    )
    assert result.returncode == 0, (
        f"{program} exited with status {result.returncode}.\n"
        f"stdout: {result.stdout}\nstderr: {result.stderr}"
    )
    return result.stdout


def expected_output(records):
    best_alpha = -1.0
    best_mse = 1e9

    for a in range(101):
        alpha = a / 100.0
        total_mse = 0.0

        for fold in range(5):
            fold_error = 0.0
            fold_count = 0
            for rec_id, f1, f2, target in records:
                if rec_id % 5 == fold:
                    pred = alpha * f1 + (1.0 - alpha) * f2
                    diff = pred - target
                    fold_error += diff * diff
                    fold_count += 1
            if fold_count > 0:
                total_mse += fold_error / fold_count

        avg_cv_mse = total_mse / 5.0
        if avg_cv_mse < best_mse:
            best_mse = avg_cv_mse
            best_alpha = alpha

    return f"Optimal alpha: {best_alpha:.2f}, Best CV MSE: {best_mse:.6f}\n"


@pytest.fixture(scope="session")
def compiled_source(tmp_path_factory):
    output = tmp_path_factory.mktemp("build") / "etl_pipeline"
    result = subprocess.run(
        ["gcc", "-O3", SOURCE, "-o", str(output)],
        text=True,
        capture_output=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        "The submitted C source does not compile with the required command.\n"
        f"stdout: {result.stdout}\nstderr: {result.stderr}"
    )
    return str(output)


def test_report_exists():
    """Check if the report file was created."""
    assert os.path.isfile(REPORT), "/home/user/report.txt is missing. Did you save the output?"


def test_report_content():
    """Check if the report contains the correct optimal alpha and MSE."""
    with open(REPORT, "r") as f:
        raw_content = f.read()
    content = raw_content.strip()

    expected_pattern = r"Optimal alpha:\s*0\.37,\s*Best CV MSE:\s*0\.334057"
    match = re.search(expected_pattern, content)
    assert match is not None, (
        "The output in /home/user/report.txt is incorrect.\n"
        "Expected it to match: 'Optimal alpha: 0.37, Best CV MSE: 0.334057'\n"
        f"Actual content: '{content}'"
    )

    assert re.fullmatch(
        r"Optimal alpha: 0\.37, Best CV MSE: 0\.334057\n?", raw_content
    ), "The report must strictly contain one correctly formatted output line."


def test_c_code_fixed(compiled_source):
    """Verify that the C code was modified to fix the data schema bug."""
    assert os.path.isfile(SOURCE), "/home/user/etl_pipeline.c is missing."
    with open(SOURCE, "r") as f:
        content = f.read()

    assert "float id;" not in content, (
        "The C code still contains 'float id;'. The ID field must be changed "
        "to an unsigned 64-bit integer type."
    )
    assert re.search(r"\bunsigned\s+long\s+long\s+id\s*;", content), (
        "The Record id field must be declared as unsigned long long."
    )


def test_binary_exists():
    """Check if the compiled binary exists."""
    assert os.path.isfile(BINARY), (
        "The compiled binary /home/user/etl_pipeline is missing. Did you compile the C code?"
    )
    assert os.access(BINARY, os.X_OK), "/home/user/etl_pipeline is not executable."
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", (
            "/home/user/etl_pipeline must be a compiled executable."
        )


def test_submitted_binary_was_run_and_report_saved():
    stdout = run_program(BINARY, "/home/user")
    assert stdout == "Optimal alpha: 0.37, Best CV MSE: 0.334057\n"
    with open(REPORT, "r") as f:
        assert f.read() == stdout, (
            "report.txt must contain the output produced by the fixed pipeline."
        )


def test_exact_64_bit_id_parsing_and_fold_assignment(compiled_source, tmp_path):
    # These valid unsigned 64-bit IDs exceed LLONG_MAX. Fold sizes and targets
    # are deliberately unequal, so truncating IDs or ignoring ID % 5 changes
    # both the selected alpha and MSE.
    base = 18446744073709551500
    fold_counts = [1, 2, 3, 10, 20]
    fold_targets = [0.0, 2.0, 4.0, 8.0, 10.0]
    records = []

    for fold, count in enumerate(fold_counts):
        for j in range(count):
            rec_id = base + fold + 5 * j
            records.append((rec_id, 10.0, 0.0, fold_targets[fold]))

    with open(tmp_path / "data.csv", "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["ID", "Feature1", "Feature2", "Target"])
        writer.writerows(records)

    expected = expected_output(records)
    assert run_program(compiled_source, str(tmp_path)) == expected, (
        "The submitted source does not parse unsigned 64-bit IDs exactly or "
        "does not assign folds using the exact ID modulo 5."
    )
    assert run_program(BINARY, str(tmp_path)) == expected, (
        "The submitted executable does not implement the fixed source behavior."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
