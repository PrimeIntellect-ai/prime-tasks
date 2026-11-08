#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import re
import subprocess

import pytest
from scipy import stats

SCRIPT_PATH = "/home/user/compare_models.py"
REPORT_PATH = "/home/user/report.json"
V1_PATH = "/home/user/model_v1.csv"
V2_PATH = "/home/user/model_v2.csv"
EXPECTED_KEYS = {"t_stat", "p_value", "ci_lower", "ci_upper"}


def get_clean_data(file_path):
    latencies = []
    with open(file_path, "r") as f:
        reader = csv.DictReader(f)
        for row in reader:
            val = row["latency_ms"]
            if not val or val.lower() == "nan":
                continue
            try:
                latencies.append(float(val))
            except ValueError:
                pass

    if not latencies:
        return []

    # Calculate P99 using linear interpolation (pandas default).
    sorted_lats = sorted(latencies)
    n = len(sorted_lats)
    idx = (n - 1) * 0.99
    lower = int(math.floor(idx))
    upper = int(math.ceil(idx))
    weight = idx - lower
    if lower == upper:
        p99 = sorted_lats[lower]
    else:
        p99 = sorted_lats[lower] * (1 - weight) + sorted_lats[upper] * weight

    return [x for x in latencies if 0 <= x <= p99]


def compute_expected(v1, v2):
    n1, n2 = len(v1), len(v2)
    mean1 = sum(v1) / n1
    mean2 = sum(v2) / n2
    var1 = sum((x - mean1) ** 2 for x in v1) / (n1 - 1)
    var2 = sum((x - mean2) ** 2 for x in v2) / (n2 - 1)
    se1_sq = var1 / n1
    se2_sq = var2 / n2
    se = math.sqrt(se1_sq + se2_sq)

    t_stat = (mean1 - mean2) / se
    df = (se1_sq + se2_sq) ** 2 / (
        (se1_sq ** 2) / (n1 - 1) + (se2_sq ** 2) / (n2 - 1)
    )
    p_value = 2.0 * stats.t.sf(abs(t_stat), df)
    margin = stats.t.ppf(0.975, df) * se
    difference = mean1 - mean2
    return {
        "t_stat": t_stat,
        "p_value": p_value,
        "ci_lower": difference - margin,
        "ci_upper": difference + margin,
    }


def run_submission():
    assert os.path.isfile(SCRIPT_PATH), f"Expected Python script {SCRIPT_PATH} does not exist."
    result = subprocess.run(
        ["python3", SCRIPT_PATH],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"{SCRIPT_PATH} failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def load_and_validate_report(v1_path, v2_path):
    assert os.path.isfile(REPORT_PATH), f"Expected output file {REPORT_PATH} does not exist."

    with open(REPORT_PATH, "r") as f:
        raw = f.read()
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        pytest.fail(f"File {REPORT_PATH} is not valid JSON.")

    assert isinstance(data, dict), "The JSON report must be an object."
    assert set(data.keys()) == EXPECTED_KEYS, (
        f"JSON keys do not match. Expected {EXPECTED_KEYS}, got {set(data.keys())}"
    )
    for key in EXPECTED_KEYS:
        assert isinstance(data[key], (int, float)), f"Value for {key} must be a number."
        assert math.isfinite(data[key]), f"Value for {key} must be finite."
        pattern = rf'"{re.escape(key)}"\s*:\s*-?(?:0|[1-9]\d*)\.\d{{4}}(?=\s*[,}}])'
        assert len(re.findall(pattern, raw)) == 1, (
            f"Value for {key} must be written as a JSON number with exactly four decimal places."
        )

    v1_clean = get_clean_data(v1_path)
    v2_clean = get_clean_data(v2_path)
    assert len(v1_clean) > 0, "No valid data found for model_v1 after cleaning."
    assert len(v2_clean) > 0, "No valid data found for model_v2 after cleaning."

    expected = compute_expected(v1_clean, v2_clean)

    # Preserve the original checks.
    assert math.isclose(data["t_stat"], expected["t_stat"], abs_tol=1e-3), (
        f't_stat mismatch: expected {expected["t_stat"]:.4f}, got {data["t_stat"]}'
    )
    assert data["ci_lower"] < data["ci_upper"], "ci_lower must be less than ci_upper"
    assert 0 <= data["p_value"] <= 1, "p_value must be between 0 and 1"

    # Every reported statistic must be the correctly rounded computed value.
    for key in EXPECTED_KEYS:
        assert math.isclose(data[key], expected[key], rel_tol=0.0, abs_tol=0.00005001), (
            f'{key} mismatch: expected {expected[key]:.4f}, got {data[key]}'
        )


def write_dataset(path, values):
    with open(path, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["request_id", "latency_ms"])
        for i, value in enumerate(values):
            writer.writerow([f"hidden_{i}", value])


def hidden_case_one():
    v1 = [100.0 + (i % 17) * 1.3 + ((i * 7) % 5) * 0.2 for i in range(180)]
    v2 = [106.0 + (i % 19) * 1.1 + ((i * 11) % 7) * 0.15 for i in range(190)]
    return v1 + ["", "nan", -10.0, 5000.0, 6000.0], v2 + ["", "nan", -8.0, 5100.0, 6200.0]


def hidden_case_two():
    v1 = [240.0 + (i % 23) * 0.85 + ((i * 5) % 9) * 0.12 for i in range(205)]
    v2 = [227.0 + (i % 13) * 1.45 + ((i * 3) % 8) * 0.18 for i in range(175)]
    return v1 + ["", "nan", -3.0, 8000.0, 9000.0], v2 + ["", "nan", -4.0, 7500.0, 8800.0]


def test_submission_on_original_and_derived_inputs():
    assert os.path.isfile(SCRIPT_PATH), f"Expected Python script {SCRIPT_PATH} does not exist."
    with open(V1_PATH, "rb") as f:
        original_v1 = f.read()
    with open(V2_PATH, "rb") as f:
        original_v2 = f.read()

    try:
        # Execute and validate against the supplied benchmark data.
        run_submission()
        load_and_validate_report(V1_PATH, V2_PATH)

        # Execute the artifact on additional inputs and derive all expected answers.
        for make_case in (hidden_case_one, hidden_case_two):
            v1, v2 = make_case()
            write_dataset(V1_PATH, v1)
            write_dataset(V2_PATH, v2)
            run_submission()
            load_and_validate_report(V1_PATH, V2_PATH)
    finally:
        with open(V1_PATH, "wb") as f:
            f.write(original_v1)
        with open(V2_PATH, "wb") as f:
            f.write(original_v2)
        # Restore the requested final report for the original supplied data.
        if os.path.isfile(SCRIPT_PATH):
            subprocess.run(
                ["python3", SCRIPT_PATH], cwd="/home/user",
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
