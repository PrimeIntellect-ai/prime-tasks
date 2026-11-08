#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import math
import subprocess
import sys
import pytest

def get_expected_results():
    script = """
import numpy as np
import json

vals = []
try:
    with open("/home/user/app_profile.log", "r") as f:
        for line in f:
            if "partial_metric" in line:
                val = float(line.split("=")[1].strip())
                vals.append(val)
except FileNotFoundError:
    print(json.dumps({"error": "Log file missing"}))
    sys.exit(0)

num_observations = len(vals)

vals_f16 = np.array(vals, dtype=np.float16)
np.random.seed(42)

sums = []
for _ in range(5000):
    np.random.shuffle(vals_f16)
    sums.append(np.sum(vals_f16))

sums = np.array(sums)
mc_mean_sum = float(np.mean(sums))
mc_std_dev = float(np.std(sums, ddof=1))

np.random.seed(123)
bootstrap_stds = []
for _ in range(2000):
    resample = np.random.choice(sums, size=len(sums), replace=True)
    bootstrap_stds.append(np.std(resample, ddof=1))

lower_ci = float(np.percentile(bootstrap_stds, 2.5))
upper_ci = float(np.percentile(bootstrap_stds, 97.5))

expected_json = {
    "num_observations": num_observations,
    "mc_mean_sum": mc_mean_sum,
    "mc_std_dev": mc_std_dev,
    "bootstrap_std_dev_ci_lower": lower_ci,
    "bootstrap_std_dev_ci_upper": upper_ci
}
print(json.dumps(expected_json))
"""
    result = subprocess.run([sys.executable, "-c", script], capture_output=True, text=True)
    if result.returncode != 0:
        pytest.fail(f"Failed to compute expected results using numpy: {result.stderr}")

    data = json.loads(result.stdout)
    if "error" in data:
        pytest.fail(data["error"])
    return data

@pytest.fixture(scope="module")
def expected_data():
    return get_expected_results()

@pytest.fixture(scope="module")
def student_data():
    report_path = "/home/user/stability_report.json"
    assert os.path.isfile(report_path), f"The report file {report_path} was not found."

    with open(report_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {report_path} does not contain valid JSON.")
    return data

def test_json_keys(student_data):
    expected_keys = {
        "num_observations",
        "mc_mean_sum",
        "mc_std_dev",
        "bootstrap_std_dev_ci_lower",
        "bootstrap_std_dev_ci_upper"
    }
    actual_keys = set(student_data.keys())
    missing = expected_keys - actual_keys
    extra = actual_keys - expected_keys

    assert not missing, f"Missing keys in JSON report: {missing}"
    assert not extra, f"Unexpected extra keys in JSON report: {extra}"

def test_num_observations(student_data, expected_data):
    actual = student_data["num_observations"]
    expected = expected_data["num_observations"]
    assert isinstance(actual, int), "'num_observations' must be an integer."
    assert actual == expected, f"Expected {expected} observations, but got {actual}."

def test_mc_mean_sum(student_data, expected_data):
    actual = student_data["mc_mean_sum"]
    expected = expected_data["mc_mean_sum"]
    assert isinstance(actual, (int, float)), "'mc_mean_sum' must be a number."
    assert math.isclose(actual, expected, abs_tol=1e-4), f"Expected mc_mean_sum ~ {expected:.4f}, but got {actual}."

def test_mc_std_dev(student_data, expected_data):
    actual = student_data["mc_std_dev"]
    expected = expected_data["mc_std_dev"]
    assert isinstance(actual, (int, float)), "'mc_std_dev' must be a number."
    assert math.isclose(actual, expected, abs_tol=1e-4), f"Expected mc_std_dev ~ {expected:.4f}, but got {actual}."

def test_bootstrap_ci(student_data, expected_data):
    actual_lower = student_data["bootstrap_std_dev_ci_lower"]
    expected_lower = expected_data["bootstrap_std_dev_ci_lower"]
    assert isinstance(actual_lower, (int, float)), "'bootstrap_std_dev_ci_lower' must be a number."
    assert math.isclose(actual_lower, expected_lower, abs_tol=1e-4), f"Expected lower CI ~ {expected_lower:.4f}, but got {actual_lower}."

    actual_upper = student_data["bootstrap_std_dev_ci_upper"]
    expected_upper = expected_data["bootstrap_std_dev_ci_upper"]
    assert isinstance(actual_upper, (int, float)), "'bootstrap_std_dev_ci_upper' must be a number."
    assert math.isclose(actual_upper, expected_upper, abs_tol=1e-4), f"Expected upper CI ~ {expected_upper:.4f}, but got {actual_upper}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
