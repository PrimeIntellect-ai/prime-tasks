#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import csv
import math
import subprocess
import pytest

PROJECT_PATH = "/home/user/analyzer"
CSV_PATH = "/home/user/sensor_data.csv"
REPORT_PATH = "/home/user/report.json"
BINARY_PATH = "/tmp/analyzer_submission"

ORIGINAL_CSV = """timestamp,sensor_id,temperature,humidity
2023-01-01T00:00:00Z,1,20.5,45.0
2023-01-01T01:00:00Z,2,21.0,50.0
2023-01-01T02:00:00Z,11,25.0,55.0
2023-01-01T03:00:00Z,3,-60.0,40.0
2023-01-01T04:00:00Z,4,22.0,110.0
2023-01-01T05:00:00Z,5,19.5,42.0
2023-01-01T06:00:00Z,1,bad,42.0
2023-01-01T07:00:00Z,6,23.0,48.0
2023-01-01T08:00:00Z,7,21.5,49.0
2023-01-01T09:00:00Z,8,20.0,47.0
"""

CHALLENGE_CSVS = [
    """timestamp,sensor_id,temperature,humidity
a,1,10,10
b,2,20,20
c,3,30,30
d,10,40,100
,4,5,50
e,0,5,50
f,5,51,50
g,6,5,-1
h,bad,5,50
i,7,bad,50
j,8,5
""",
    """timestamp,sensor_id,temperature,humidity
x,1,-10,30
y,5,-8,40
z,10,-12,50
badid,11,21.5,50
badtemp,2,-50.1,50
badhumidity,3,0,100.1
missingtemp,4,,25
""",
    """timestamp,sensor_id,temperature,humidity
p,1,20.5,0
q,2,21,20
r,3,21.5,40
s,4,22,60
t,5,22.5,80
u,6,23,100
blanktimestamp,7,24,
,8,24,50
notinteger,1.5,24,50
""",
]

@pytest.fixture(scope="session", autouse=True)
def compile_go_program():
    assert os.path.isdir(PROJECT_PATH), f"The Go project directory {PROJECT_PATH} does not exist."
    go_sources = [
        name for name in os.listdir(PROJECT_PATH)
        if name.endswith(".go") and os.path.isfile(os.path.join(PROJECT_PATH, name))
    ]
    assert go_sources, f"No Go source files were found in {PROJECT_PATH}."

    env = os.environ.copy()
    env["GO111MODULE"] = "off"
    result = subprocess.run(
        ["go", "build", "-o", BINARY_PATH, "."],
        cwd=PROJECT_PATH,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, f"The Go project did not compile successfully:\n{result.stderr}"
    assert os.path.isfile(BINARY_PATH), "Compiling the Go project did not produce an executable."
    assert os.access(BINARY_PATH, os.X_OK), "The compiled Go program is not executable."


def calculate_expected(csv_path):
    valid_temperatures = []
    with open(csv_path, "r") as f:
        reader = csv.DictReader(f)
        for row in reader:
            try:
                if not row["timestamp"].strip():
                    continue
                sensor_id = int(row["sensor_id"])
                if not (1 <= sensor_id <= 10):
                    continue
                temperature = float(row["temperature"])
                if not (-50.0 <= temperature <= 50.0):
                    continue
                humidity = float(row["humidity"])
                if not (0.0 <= humidity <= 100.0):
                    continue
                valid_temperatures.append(temperature)
            except (ValueError, KeyError, TypeError):
                continue

    n = len(valid_temperatures)
    assert n > 1, "Test data must contain at least two valid rows."
    mean_temp = sum(valid_temperatures) / n
    variance = sum((x - mean_temp) ** 2 for x in valid_temperatures) / (n - 1)
    std_dev = math.sqrt(variance)
    margin_of_error = 1.96 * (std_dev / math.sqrt(n))
    ci_lower = mean_temp - margin_of_error
    ci_upper = mean_temp + margin_of_error
    return n, mean_temp, ci_lower, ci_upper, ci_lower <= 21.5 <= ci_upper


def assert_report_matches(csv_path):
    n, mean_temp, ci_lower, ci_upper, model_validated = calculate_expected(csv_path)
    assert os.path.exists(REPORT_PATH), f"The file {REPORT_PATH} does not exist."
    assert os.path.isfile(REPORT_PATH), f"{REPORT_PATH} is not a valid file."
    with open(REPORT_PATH, "r") as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {REPORT_PATH} does not contain valid JSON.")

    assert "valid_rows" in report, "Key 'valid_rows' is missing from the JSON report."
    assert report["valid_rows"] == n, f"Expected 'valid_rows' to be {n}, got {report['valid_rows']}."
    assert "mean_temperature" in report, "Key 'mean_temperature' is missing from the JSON report."
    assert math.isclose(report["mean_temperature"], round(mean_temp, 4), abs_tol=0.0002), \
        f"Expected 'mean_temperature' to be approx {round(mean_temp, 4)}, got {report['mean_temperature']}."
    assert "ci_lower" in report, "Key 'ci_lower' is missing from the JSON report."
    assert math.isclose(report["ci_lower"], round(ci_lower, 4), abs_tol=0.0002), \
        f"Expected 'ci_lower' to be approx {round(ci_lower, 4)}, got {report['ci_lower']}."
    assert "ci_upper" in report, "Key 'ci_upper' is missing from the JSON report."
    assert math.isclose(report["ci_upper"], round(ci_upper, 4), abs_tol=0.0002), \
        f"Expected 'ci_upper' to be approx {round(ci_upper, 4)}, got {report['ci_upper']}."
    assert "model_validated" in report, "Key 'model_validated' is missing from the JSON report."
    assert report["model_validated"] is model_validated, \
        f"Expected 'model_validated' to be {model_validated}, got {report['model_validated']}."


def run_compiled_program():
    if os.path.lexists(REPORT_PATH):
        os.remove(REPORT_PATH)
    result = subprocess.run(
        [BINARY_PATH],
        cwd=PROJECT_PATH,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, f"The compiled Go program failed:\n{result.stderr}"
    assert os.path.isfile(REPORT_PATH), "The compiled Go program did not generate /home/user/report.json."


def test_report_json_exists():
    report_path = "/home/user/report.json"
    assert os.path.exists(report_path), f"The file {report_path} does not exist."
    assert os.path.isfile(report_path), f"{report_path} is not a valid file."


def test_compiled_go_program_handles_derived_inputs():
    try:
        for challenge in CHALLENGE_CSVS:
            with open(CSV_PATH, "w") as f:
                f.write(challenge)
            run_compiled_program()
            assert_report_matches(CSV_PATH)
    finally:
        with open(CSV_PATH, "w") as f:
            f.write(ORIGINAL_CSV)
        run_compiled_program()


def test_report_json_content():
    csv_path = "/home/user/sensor_data.csv"
    assert os.path.exists(csv_path), f"The original data file {csv_path} is missing."

    valid_temperatures = []
    with open(csv_path, "r") as f:
        reader = csv.DictReader(f)
        for row in reader:
            try:
                # Check timestamp
                if not row["timestamp"].strip():
                    continue
                # Check sensor_id
                sensor_id = int(row["sensor_id"])
                if not (1 <= sensor_id <= 10):
                    continue
                # Check temperature
                temperature = float(row["temperature"])
                if not (-50.0 <= temperature <= 50.0):
                    continue
                # Check humidity
                humidity = float(row["humidity"])
                if not (0.0 <= humidity <= 100.0):
                    continue

                valid_temperatures.append(temperature)
            except (ValueError, KeyError, TypeError):
                # Discard rows with missing or unparseable data
                continue

    n = len(valid_temperatures)
    assert n > 0, "No valid rows found in the CSV data."

    # Calculate statistics
    mean_temp = sum(valid_temperatures) / n
    variance = sum((x - mean_temp) ** 2 for x in valid_temperatures) / (n - 1)
    std_dev = math.sqrt(variance)

    margin_of_error = 1.96 * (std_dev / math.sqrt(n))
    ci_lower = mean_temp - margin_of_error
    ci_upper = mean_temp + margin_of_error

    model_validated = (ci_lower <= 21.5 <= ci_upper)

    # Read and validate the generated JSON report
    report_path = "/home/user/report.json"
    with open(report_path, "r") as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {report_path} does not contain valid JSON.")

    # Check keys and values
    assert "valid_rows" in report, "Key 'valid_rows' is missing from the JSON report."
    assert report["valid_rows"] == n, f"Expected 'valid_rows' to be {n}, got {report['valid_rows']}."

    assert "mean_temperature" in report, "Key 'mean_temperature' is missing from the JSON report."
    assert math.isclose(report["mean_temperature"], round(mean_temp, 4), abs_tol=0.0002), \
        f"Expected 'mean_temperature' to be approx {round(mean_temp, 4)}, got {report['mean_temperature']}."

    assert "ci_lower" in report, "Key 'ci_lower' is missing from the JSON report."
    assert math.isclose(report["ci_lower"], round(ci_lower, 4), abs_tol=0.0002), \
        f"Expected 'ci_lower' to be approx {round(ci_lower, 4)}, got {report['ci_lower']}."

    assert "ci_upper" in report, "Key 'ci_upper' is missing from the JSON report."
    assert math.isclose(report["ci_upper"], round(ci_upper, 4), abs_tol=0.0002), \
        f"Expected 'ci_upper' to be approx {round(ci_upper, 4)}, got {report['ci_upper']}."

    assert "model_validated" in report, "Key 'model_validated' is missing from the JSON report."
    assert report["model_validated"] is model_validated, \
        f"Expected 'model_validated' to be {model_validated}, got {report['model_validated']}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
