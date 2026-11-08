#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import subprocess
import math

def test_analyze_script_exists_and_executable():
    script_path = '/home/user/analyze.sh'
    assert os.path.isfile(script_path), f"The script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"The script {script_path} is not executable."

def test_run_analyze_script():
    script_path = '/home/user/analyze.sh'
    result = subprocess.run([script_path], capture_output=True, text=True, cwd='/home/user')
    assert result.returncode == 0, f"analyze.sh failed with return code {result.returncode}. stderr:\n{result.stderr}"

def test_report_json_exists():
    report_path = '/home/user/report.json'
    assert os.path.isfile(report_path), f"The report file {report_path} was not created."

def test_report_json_contents():
    report_path = '/home/user/report.json'
    with open(report_path, 'r') as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            assert False, f"{report_path} does not contain valid JSON."

    # Compute expected values using a subprocess to adhere to the standard-library-only rule for the test script
    checker_script = """
import numpy as np
from scipy import stats
import json

def parse_val(x):
    return np.nan if b'TIMEOUT' in x else float(x)

v1_clean = np.loadtxt('/home/user/v1_latency.csv', delimiter=',', skiprows=1, usecols=1, converters={1: parse_val})
v2_clean = np.loadtxt('/home/user/v2_latency.csv', delimiter=',', skiprows=1, usecols=1, converters={1: parse_val})

v1_clean = v1_clean[~np.isnan(v1_clean)]
v2_clean = v2_clean[~np.isnan(v2_clean)]

n = len(v1_clean)
yf = np.fft.rfft(v1_clean - np.mean(v1_clean))
xf = np.fft.rfftfreq(n, d=0.1)
dominant_freq = xf[np.argmax(np.abs(yf))]

t_stat, p_val = stats.ttest_ind(v1_clean, v2_clean, equal_var=False)
w_dist = stats.wasserstein_distance(v1_clean, v2_clean)

expected = {
    "dominant_freq_v1_hz": round(dominant_freq, 2),
    "t_test_p_value": round(p_val, 4),
    "wasserstein_distance": round(w_dist, 4)
}
print(json.dumps(expected))
"""
    result = subprocess.run(['python3', '-c', checker_script], capture_output=True, text=True)
    assert result.returncode == 0, f"Failed to compute expected values. stderr: {result.stderr}"

    expected = json.loads(result.stdout)

    keys = ["dominant_freq_v1_hz", "t_test_p_value", "wasserstein_distance"]
    for k in keys:
        assert k in report, f"Key '{k}' is missing in {report_path}."

        actual_val = report[k]
        expected_val = expected[k]

        assert isinstance(actual_val, (int, float)), f"Value for '{k}' must be a number."
        assert math.isclose(actual_val, expected_val, abs_tol=1e-4), \
            f"Value for '{k}' is {actual_val}, but expected approximately {expected_val}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
