#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import random
import re
import stat
import subprocess

DATASET = "/home/user/dataset.csv"
REPORT = "/home/user/report.txt"
PREDICT = "/home/user/predict.sh"


def derive_expected_values():
    with open(DATASET, newline="") as f:
        rows = list(csv.DictReader(f))

    assert rows, "dataset.csv contains no data rows"
    features = ["sensor_A", "sensor_B", "sensor_C"]
    y = [float(row["target"]) for row in rows]
    n = len(rows)

    def correlation(feature):
        x = [float(row[feature]) for row in rows]
        sx = sum(x)
        sy = sum(y)
        sxx = sum(v * v for v in x)
        syy = sum(v * v for v in y)
        sxy = sum(a * b for a, b in zip(x, y))
        numerator = n * sxy - sx * sy
        denominator = math.sqrt((n * sxx - sx * sx) * (n * syy - sy * sy))
        assert denominator != 0, f"Cannot calculate correlation for {feature}"
        return numerator / denominator

    best_feature = max(features, key=lambda feature: abs(correlation(feature)))
    x = [float(row[best_feature]) for row in rows]
    sx = sum(x)
    sy = sum(y)
    sxx = sum(v * v for v in x)
    sxy = sum(a * b for a, b in zip(x, y))
    denominator = n * sxx - sx * sx
    assert denominator != 0, "Cannot fit a regression to a constant feature"

    slope = (n * sxy - sx * sy) / denominator
    intercept = (sy - slope * sx) / n
    mse = sum((actual - (slope * value + intercept)) ** 2
              for value, actual in zip(x, y)) / n

    return best_feature, f"{slope:.2f}", f"{intercept:.2f}", f"{mse:.2f}"


EXPECTED_FEATURE, EXPECTED_SLOPE, EXPECTED_INTERCEPT, EXPECTED_MSE = derive_expected_values()


def test_report_exists():
    assert os.path.isfile(REPORT), f"File {REPORT} is missing."


def test_report_content():
    with open(REPORT, "r") as f:
        content = f.read()

    pattern = (
        r"Best Feature: ([^\r\n]+)\r?\n"
        r"Slope: (-?(?:\d+\.\d{2}))\r?\n"
        r"Intercept: (-?(?:\d+\.\d{2}))\r?\n"
        r"MSE: (-?(?:\d+\.\d{2}))(?:\r?\n)?\Z"
    )
    match = re.fullmatch(pattern, content)
    assert match is not None, "report.txt does not exactly match the required four-line format"

    best_feature, slope, intercept, mse = match.groups()
    assert best_feature.strip() == EXPECTED_FEATURE, (
        f"Expected Best Feature to be '{EXPECTED_FEATURE}', got '{best_feature.strip()}'"
    )
    assert slope == EXPECTED_SLOPE, f"Expected Slope to be '{EXPECTED_SLOPE}', got '{slope}'"
    assert intercept == EXPECTED_INTERCEPT, (
        f"Expected Intercept to be '{EXPECTED_INTERCEPT}', got '{intercept}'"
    )
    assert mse == EXPECTED_MSE, f"Expected MSE to be '{EXPECTED_MSE}', got '{mse}'"


def test_predict_script_exists_and_executable():
    assert os.path.isfile(PREDICT), f"Script {PREDICT} is missing."
    st = os.stat(PREDICT)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {PREDICT} is not executable."


def run_prediction(argument):
    try:
        result = subprocess.run(
            [PREDICT, argument],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=True,
            timeout=5,
        )
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired, OSError) as exc:
        assert False, f"Execution of {PREDICT} for input {argument} failed: {exc}"

    output = result.stdout.strip()
    expected = f"{float(EXPECTED_SLOPE) * float(argument) + float(EXPECTED_INTERCEPT):.2f}"
    assert output == expected, (
        f"Expected predict.sh {argument} to output '{expected}', got '{output}'"
    )


def test_predict_script_output():
    # Preserve the original benchmark cases.
    run_prediction("5.0")
    run_prediction("10.0")

    # Exercise numerical inference on values unavailable when the agent acts.
    secure_random = random.SystemRandom()
    arguments = []
    while len(arguments) < 12:
        value = secure_random.uniform(-250.0, 250.0)
        argument = f"{value:.6f}"
        if argument not in arguments and argument not in {"5.000000", "10.000000"}:
            arguments.append(argument)

    for argument in arguments:
        run_prediction(argument)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
