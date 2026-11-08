#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import random
import re
import subprocess
import tempfile

import pytest

RAW_DIR = "/home/user/raw_data"
CLEAN_DIR = "/home/user/cleaned_data"
SCRIPT = "/home/user/run_experiments.sh"
SOURCE = "/home/user/cleaner.c"
EXECUTABLE = "/home/user/cleaner"
LOG = "/home/user/experiment_log.csv"
EXPECTED_DATASETS = ["sensor_A.csv", "sensor_B.csv", "sensor_C.csv"]


def read_raw(path):
    rows = []
    with open(path, newline="") as f:
        for row in csv.reader(f):
            assert len(row) == 2, f"Malformed input row in {path}: {row}"
            rows.append((float(row[0]), float(row[1])))
    return rows


def oracle(rows):
    assert rows
    n = len(rows)
    mean_x = sum(x for x, _ in rows) / n
    mean_y = sum(y for _, y in rows) / n
    denominator = sum((x - mean_x) ** 2 for x, _ in rows)
    assert denominator != 0
    slope = sum((x - mean_x) * (y - mean_y) for x, y in rows) / denominator
    intercept = mean_y - slope * mean_x
    kept = []
    removed = 0
    for x, y in rows:
        residual = abs(y - (slope * x + intercept))
        if residual > 15.0:
            removed += 1
        else:
            kept.append((f"{x:.4f}", f"{y:.4f}"))
    return slope, intercept, removed, kept


RAW_SNAPSHOT = {
    name: read_raw(os.path.join(RAW_DIR, name)) for name in EXPECTED_DATASETS
}


@pytest.fixture(scope="session", autouse=True)
def execute_pipeline():
    assert os.path.isfile(SCRIPT), f"Bash script {SCRIPT} does not exist."
    assert os.access(SCRIPT, os.X_OK), f"Bash script {SCRIPT} is not executable."
    result = subprocess.run([SCRIPT], capture_output=True, text=True, timeout=60)
    assert result.returncode == 0, f"Script execution failed with error:\n{result.stderr}"


def test_experiment_log_exists_and_header():
    assert os.path.isfile(LOG), f"Log file {LOG} was not created."
    with open(LOG, newline="") as f:
        reader = csv.reader(f)
        header = next(reader, None)
    expected_header = ["dataset", "slope", "intercept", "removed_outliers"]
    assert header == expected_header, f"Incorrect header in {LOG}. Expected {expected_header}, got {header}."


def test_cleaned_data_files_created_and_correct():
    for name in EXPECTED_DATASETS:
        output = os.path.join(CLEAN_DIR, "clean_" + name)
        assert os.path.isfile(output), f"Cleaned data file {output} is missing."
        with open(output, newline="") as f:
            actual = list(csv.reader(f))
        expected = [list(row) for row in oracle(RAW_SNAPSHOT[name])[3]]
        assert actual == expected, f"Cleaned contents for {name} do not match OLS residual filtering."


def test_experiment_log_contents():
    assert os.path.isfile(LOG), f"Log file {LOG} does not exist."
    with open(LOG, newline="") as f:
        rows = list(csv.DictReader(f))

    assert len(rows) == 3, f"Expected exactly 3 data rows in {LOG}, found {len(rows)}."
    by_name = {row["dataset"]: row for row in rows}
    assert set(by_name) == set(EXPECTED_DATASETS), "Experiment log does not contain exactly the expected datasets."

    four_decimals = re.compile(r"^-?\d+\.\d{4}$")
    for name in EXPECTED_DATASETS:
        row = by_name[name]
        assert four_decimals.fullmatch(row["slope"]), f"Slope for {name} is not formatted to four decimals."
        assert four_decimals.fullmatch(row["intercept"]), f"Intercept for {name} is not formatted to four decimals."
        expected_slope, expected_intercept, expected_removed, _ = oracle(RAW_SNAPSHOT[name])
        assert math.isclose(float(row["slope"]), expected_slope, abs_tol=0.00005), f"Incorrect slope for {name}."
        assert math.isclose(float(row["intercept"]), expected_intercept, abs_tol=0.00005), f"Incorrect intercept for {name}."
        assert int(row["removed_outliers"]) == expected_removed, f"Incorrect outlier count for {name}."

    sensor_a = by_name.get("sensor_A.csv")
    assert sensor_a is not None, "Log entry for 'sensor_A.csv' not found in experiment_log.csv."
    try:
        slope = float(sensor_a["slope"])
        outliers = int(sensor_a["removed_outliers"])
    except ValueError as exc:
        pytest.fail(f"Could not parse slope or outliers as numbers for sensor_A.csv: {exc}")
    assert 2.0 < slope < 3.0, f"Calculated slope for sensor_A.csv is {slope}, expected a value around 2.5."
    assert outliers == 4, f"Removed outliers for sensor_A.csv is {outliers}, expected exactly 4."


def test_c_program_compilation_and_executable():
    assert os.path.isfile(SOURCE), f"C source file {SOURCE} does not exist."
    assert os.path.isfile(EXECUTABLE), f"Compiled executable {EXECUTABLE} does not exist."
    assert os.access(EXECUTABLE, os.X_OK), f"Compiled binary {EXECUTABLE} is not executable."


def test_c_source_on_independent_runtime_data():
    with tempfile.TemporaryDirectory(prefix="cleaner_verify_") as tempdir:
        independent_binary = os.path.join(tempdir, "cleaner_from_source")
        build = subprocess.run(
            ["gcc", SOURCE, "-o", independent_binary, "-lm"],
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert build.returncode == 0, f"Independent compilation failed:\n{build.stderr}"
        assert os.access(independent_binary, os.X_OK)

        rng = random.SystemRandom()
        for case in range(2):
            true_m = rng.uniform(-3.5, 3.5)
            true_b = rng.uniform(-20.0, 20.0)
            generated = []
            for i in range(45 + case * 8):
                x = rng.uniform(-80.0, 80.0) + i * 0.013
                y = true_m * x + true_b + rng.uniform(-1.5, 1.5)
                generated.append((f"{x:.4f}", f"{y:.4f}"))
            for magnitude in (75.0, -90.0, 110.0):
                x = rng.uniform(-70.0, 70.0)
                y = true_m * x + true_b + magnitude
                generated.append((f"{x:.4f}", f"{y:.4f}"))
            rng.shuffle(generated)

            input_path = os.path.join(tempdir, f"runtime_case_{case}.csv")
            output_path = os.path.join(tempdir, f"runtime_clean_{case}.csv")
            with open(input_path, "w", newline="") as f:
                csv.writer(f).writerows(generated)

            numeric_rows = [(float(x), float(y)) for x, y in generated]
            expected_m, expected_b, expected_removed, expected_kept = oracle(numeric_rows)
            run = subprocess.run(
                [independent_binary, input_path, output_path],
                capture_output=True,
                text=True,
                timeout=20,
            )
            assert run.returncode == 0, f"Cleaner failed on independent input:\n{run.stderr}"
            stdout_lines = run.stdout.splitlines()
            assert len(stdout_lines) == 1, f"Cleaner must print exactly one summary line, got: {run.stdout!r}"
            match = re.fullmatch(r"(.+),m=(-?\d+\.\d{4}),b=(-?\d+\.\d{4}),outliers=(\d+)", stdout_lines[0])
            assert match, f"Cleaner summary has incorrect format: {stdout_lines[0]!r}"
            assert match.group(1) in (input_path, os.path.basename(input_path)), "Summary names the wrong input file."
            assert math.isclose(float(match.group(2)), expected_m, abs_tol=0.00005), "Cleaner reported an incorrect slope."
            assert math.isclose(float(match.group(3)), expected_b, abs_tol=0.00005), "Cleaner reported an incorrect intercept."
            assert int(match.group(4)) == expected_removed, "Cleaner reported an incorrect outlier count."
            assert os.path.isfile(output_path), "Cleaner did not create its requested output file."
            with open(output_path, newline="") as f:
                actual_kept = list(csv.reader(f))
            assert actual_kept == [list(row) for row in expected_kept], "Cleaner output does not contain exactly the non-outlier points formatted to four decimals."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
