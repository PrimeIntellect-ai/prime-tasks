#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import filecmp
import math
import os
import random
import re
import shutil
import statistics
import subprocess
import tempfile

import pandas as pd
import pytest

IMPUTED = "/home/user/imputed.csv"
SENSOR = "/home/user/sensor_data.csv"
SOURCE = "/home/user/calc_metric.c"
METRIC = "/home/user/metric.txt"
EXECUTABLE = "/tmp/calc_metric_test"


def test_imputed_csv_exists():
    assert os.path.exists(IMPUTED), f"Missing generated dataset at {IMPUTED}"
    assert os.path.isfile(IMPUTED), f"{IMPUTED} is not a file"
    assert os.path.getsize(IMPUTED) > 0, f"{IMPUTED} is empty"


def test_c_source_exists():
    assert os.path.exists(SOURCE), f"Missing C source file at {SOURCE}"
    assert os.path.isfile(SOURCE), f"{SOURCE} is not a file"


def test_metric_txt_exists_and_valid():
    assert os.path.exists(METRIC), f"Missing metric output file at {METRIC}"
    assert os.path.isfile(METRIC), f"{METRIC} is not a file"

    with open(METRIC, "r") as f:
        content = f.read().strip()

    try:
        float(content)
    except ValueError:
        pytest.fail(f"Content of {METRIC} is not a valid float: '{content}'")


def make_pristine_sensor(path):
    random.seed(42)
    with open(path, "w") as f:
        f.write("id,timestamp,value\n")
        for i in range(10000):
            r = random.random()
            if r < 0.05:
                val = ""
            elif r < 0.10:
                val = random.choice([-50.0, 1500.0])
            else:
                val = random.gauss(50.0, 15.0)
            f.write(f"{i},2023-01-01T12:00:00Z,{val}\n")


def test_imputed_is_actual_imputer_output():
    assert os.path.isfile(SENSOR), f"Missing supplied sensor data at {SENSOR}"
    assert os.path.isfile("/app/imputer"), "Missing proprietary imputer"

    pristine_sensor = "/tmp/pristine_sensor_data.csv"
    expected_imputed = "/tmp/expected_imputed.csv"
    make_pristine_sensor(pristine_sensor)

    assert filecmp.cmp(SENSOR, pristine_sensor, shallow=False), \
        "The supplied sensor_data.csv was modified"

    result = subprocess.run(
        ["/app/imputer", pristine_sensor, expected_imputed],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, \
        f"/app/imputer failed during verification: {result.stderr}"
    assert filecmp.cmp(IMPUTED, expected_imputed, shallow=False), \
        "imputed.csv is not the output of /app/imputer on the supplied sensor data"


def test_metric_accuracy():
    assert os.path.exists(IMPUTED), f"Cannot verify metric without {IMPUTED}"
    assert os.path.exists(METRIC), f"Cannot verify metric without {METRIC}"

    df = pd.read_csv(IMPUTED)
    assert 'value' in df.columns, f"Column 'value' not found in {IMPUTED}"

    valid_rows = df[(df['value'] >= 0.0) & (df['value'] <= 1000.0)]
    expected_std = valid_rows['value'].std(ddof=1)

    with open(METRIC, 'r') as f:
        agent_val = float(f.read().strip())

    error = abs(expected_std - agent_val)
    threshold = 0.005
    assert error <= threshold, (
        f"Metric threshold exceeded! Absolute error is {error:.6f} "
        f"(Threshold <= {threshold}). Expected {expected_std:.6f}, "
        f"got {agent_val:.6f}."
    )


def parse_single_number(text):
    text = text.strip()
    pattern = r"[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?"
    if not re.fullmatch(pattern, text):
        return None
    value = float(text)
    return value if math.isfinite(value) else None


def run_program(input_path):
    # Support both a normal argv[1] interface and a program which is hard-coded
    # to read /home/user/imputed.csv. In either case, stale metric output cannot
    # satisfy the check because it is replaced before every attempt.
    for args in ([EXECUTABLE, input_path], [EXECUTABLE]):
        with open(METRIC, "w") as f:
            f.write("not-a-result\n")

        try:
            result = subprocess.run(
                args,
                cwd="/home/user",
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=10,
            )
        except subprocess.TimeoutExpired:
            continue

        if result.returncode != 0:
            continue

        value = parse_single_number(result.stdout)
        if value is not None:
            return value

        try:
            with open(METRIC, "r") as f:
                value = parse_single_number(f.read())
        except OSError:
            value = None
        if value is not None:
            return value

    pytest.fail("Compiled calc_metric.c did not produce a single floating-point result")


def csv_for_values(values):
    rows = ["id,timestamp,value"]
    parsed = []
    for i, value in enumerate(values):
        rendered = f"{value:.10f}"
        parsed.append(float(rendered))
        rows.append(f"{i},2024-02-03T04:05:06Z,{rendered}")
    return ("\n".join(rows) + "\n").encode(), parsed


def test_compile_and_exercise_c_program():
    compile_result = subprocess.run(
        ["gcc", "-std=c11", "-O2", "-Wall", "-Wextra", SOURCE, "-o", EXECUTABLE, "-lm"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert compile_result.returncode == 0, \
        f"calc_metric.c did not compile:\n{compile_result.stderr}"

    with open(IMPUTED, "rb") as f:
        original_imputed = f.read()
    with open(METRIC, "rb") as f:
        original_metric = f.read()

    try:
        # First verify that the compiled program reproduces the submitted metric.
        df = pd.read_csv(IMPUTED)
        valid = df[(df["value"] >= 0.0) & (df["value"] <= 1000.0)]["value"]
        expected_real = float(valid.std(ddof=1))
        actual_real = run_program(IMPUTED)
        assert abs(actual_real - expected_real) <= 0.005, \
            f"Compiled C program returned {actual_real}, expected {expected_real} on imputed.csv"

        # Then use unpredictable inputs to verify sample standard deviation and
        # complete exclusion of values outside [0, 1000].
        rng = random.SystemRandom()
        for case_number in range(3):
            values = [rng.uniform(1.0, 999.0) for _ in range(rng.randint(7, 18))]
            values.extend([0.0, 1000.0, -rng.uniform(0.01, 500.0), rng.uniform(1000.01, 2000.0)])
            rng.shuffle(values)
            csv_bytes, parsed = csv_for_values(values)
            case_path = f"/tmp/calc_metric_case_{case_number}.csv"
            with open(case_path, "wb") as f:
                f.write(csv_bytes)
            with open(IMPUTED, "wb") as f:
                f.write(csv_bytes)

            valid_values = [v for v in parsed if 0.0 <= v <= 1000.0]
            expected = statistics.stdev(valid_values)
            actual = run_program(case_path)
            assert abs(actual - expected) <= 0.005, (
                f"Compiled C program failed generated case {case_number}: "
                f"expected {expected}, got {actual}"
            )
    finally:
        with open(IMPUTED, "wb") as f:
            f.write(original_imputed)
        with open(METRIC, "wb") as f:
            f.write(original_metric)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
