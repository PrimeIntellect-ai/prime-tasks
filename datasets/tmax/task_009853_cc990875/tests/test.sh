#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import random
import subprocess
import tempfile

import pytest

SOURCE_PATH = "/home/user/etl_validator.cpp"
EXEC_PATH = "/home/user/etl_validator"
INPUT_PATH = "/home/user/input_data.csv"
LOG_PATH = "/home/user/etl_log.txt"


def expected_logs_for(path):
    expected_logs = []
    valid_rows_count = 0

    with open(path, "r", newline="") as f:
        reader = csv.reader(f)
        header = next(reader, None)
        assert header == ["id", "prior_prob", "likelihood", "evidence", "expected_posterior"], "Input CSV header is incorrect."

        for row in reader:
            if not row:
                continue

            row_id = int(row[0])
            prior_prob = float(row[1])
            likelihood = float(row[2])
            evidence = float(row[3])
            expected_posterior = float(row[4])

            if prior_prob < 0.0 or prior_prob > 1.0 or evidence == 0.0:
                expected_logs.append(f"SCHEMA_ERROR: id {row_id}")
                continue

            posterior = (likelihood * prior_prob) / evidence
            if abs(posterior - expected_posterior) > 0.0001:
                expected_logs.append(f"ACCURACY_ERROR: id {row_id}")

            valid_rows_count += 1

    expected_logs.append(f"BENCHMARK_PROCESSED: {valid_rows_count} valid rows")
    return expected_logs


def run_and_check(executable, expected):
    if os.path.exists(LOG_PATH):
        os.remove(LOG_PATH)

    result = subprocess.run(
        [executable],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"{executable} exited with {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(LOG_PATH), f"Program did not create {LOG_PATH}"

    with open(LOG_PATH, "r") as f:
        actual = [line.strip() for line in f if line.strip()]

    assert actual == expected, (
        f"Log contents do not match expected output.\n"
        f"Expected:\n{chr(10).join(expected)}\n\n"
        f"Actual:\n{chr(10).join(actual)}"
    )


def write_rows(rows):
    with open(INPUT_PATH, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["id", "prior_prob", "likelihood", "evidence", "expected_posterior"])
        writer.writerows(rows)


def test_source_and_executable_exist():
    """Ensure the C++ source file and the compiled executable exist."""
    assert os.path.isfile(SOURCE_PATH), f"C++ source file missing: {SOURCE_PATH}"
    assert os.path.isfile(EXEC_PATH), f"Compiled executable missing: {EXEC_PATH}"
    assert os.access(EXEC_PATH, os.X_OK), f"File is not executable: {EXEC_PATH}"

    with open(EXEC_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Compiled executable is not an ELF binary"


def test_etl_log_contents():
    """Run the submitted executable and validate its output on the supplied CSV."""
    assert os.path.isfile(INPUT_PATH), f"Input data file missing: {INPUT_PATH}"
    expected = expected_logs_for(INPUT_PATH)
    run_and_check(EXEC_PATH, expected)


def test_executable_and_source_on_derived_inputs():
    """Exercise both the installed executable and a fresh build of the submitted source."""
    with open(INPUT_PATH, "rb") as f:
        original_input = f.read()

    rebuilt = os.path.join(tempfile.gettempdir(), "etl_validator_rebuilt")
    compile_result = subprocess.run(
        ["g++", "-O3", "-o", rebuilt, SOURCE_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert compile_result.returncode == 0, (
        f"Submitted C++ source does not compile with the required command.\n"
        f"stdout:\n{compile_result.stdout}\nstderr:\n{compile_result.stderr}"
    )

    executables = [EXEC_PATH, rebuilt]

    try:
        edge_rows = [
            [901, "0.0", "0.7", "0.5", "0.0001"],
            [902, "1.0", "0.25", "0.5", "0.5"],
            [903, "0.5", "0.4", "0.2", "1.000101"],
            [904, "1.000001", "0.2", "0.4", "0.5"],
            [905, "-0.000001", "0.2", "0.4", "0.0"],
            [906, "0.5", "0.4", "0.0", "0.0"],
            [907, "0.2", "0.3", "-0.5", "-0.12"],
        ]
        write_rows(edge_rows)
        expected = expected_logs_for(INPUT_PATH)
        for executable in executables:
            run_and_check(executable, expected)

        rng = random.Random(int.from_bytes(os.urandom(16), "big"))
        base_id = rng.randint(10000, 90000)
        generated_rows = []
        for index in range(24):
            prior_text = f"{rng.uniform(0.05, 0.95):.6f}"
            likelihood_text = f"{rng.uniform(0.05, 0.95):.6f}"
            evidence_text = f"{rng.uniform(0.05, 0.95):.6f}"
            posterior = (float(likelihood_text) * float(prior_text)) / float(evidence_text)
            if index in (4, 13, 21):
                posterior += 0.002 + rng.random() * 0.004
            generated_rows.append([
                base_id + index,
                prior_text,
                likelihood_text,
                evidence_text,
                f"{posterior:.12f}",
            ])

        generated_rows.insert(3, [base_id + 100, "1.25", "0.4", "0.3", "1.0"])
        generated_rows.insert(11, [base_id + 101, "-0.25", "0.4", "0.3", "-1.0"])
        generated_rows.insert(19, [base_id + 102, "0.5", "0.4", "0.0", "0.0"])

        write_rows(generated_rows)
        expected = expected_logs_for(INPUT_PATH)
        for executable in executables:
            run_and_check(executable, expected)
    finally:
        with open(INPUT_PATH, "wb") as f:
            f.write(original_input)
        if os.path.exists(LOG_PATH):
            os.remove(LOG_PATH)
        if os.path.exists(rebuilt):
            os.remove(rebuilt)

    # Leave the supplied dataset's requested output in place.
    run_and_check(EXEC_PATH, expected_logs_for(INPUT_PATH))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
