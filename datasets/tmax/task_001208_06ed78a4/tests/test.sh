#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import json
import gzip
import glob
import math
import os
import pytest

def test_report_json_exists():
    """Verify that the report.json file was created."""
    assert os.path.isfile('/home/user/report.json'), "The file /home/user/report.json does not exist."

def test_report_json_values():
    """Verify that the calculated values in report.json match the ground truth."""
    report_path = '/home/user/report.json'
    assert os.path.isfile(report_path), "The file /home/user/report.json does not exist."

    with open(report_path, 'r') as f:
        try:
            ans = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("The file /home/user/report.json is not valid JSON.")

    required_keys = ["mse_a", "mse_b", "t_stat", "is_significant"]
    for key in required_keys:
        assert key in ans, f"Key '{key}' is missing from report.json."

    # Ground truth calculation
    y_true, y_a, y_b = [], [], []
    files = sorted(glob.glob('/home/user/artifacts/part-*.csv.gz'))
    assert len(files) > 0, "No artifact files found in /home/user/artifacts/"

    for f in files:
        with gzip.open(f, 'rt') as file:
            next(file) # skip header
            for line in file:
                parts = line.strip().split(',')
                if len(parts) >= 4:
                    y_true.append(float(parts[1]))
                    y_a.append(float(parts[2]))
                    y_b.append(float(parts[3]))

    N = len(y_true)
    assert N > 0, "No records found in the artifact files."

    se_a_sum = 0
    se_b_sum = 0
    D = []
    for i in range(N):
        se_a = (y_true[i] - y_a[i])**2
        se_b = (y_true[i] - y_b[i])**2
        se_a_sum += se_a
        se_b_sum += se_b
        D.append(se_a - se_b)

    mse_a = se_a_sum / N
    mse_b = se_b_sum / N

    mean_d = sum(D) / N
    var_d = sum((x - mean_d)**2 for x in D) / (N - 1)
    std_d = math.sqrt(var_d)
    t_stat = mean_d / (std_d / math.sqrt(N))

    expected_is_significant = (t_stat > 1.96)

    assert abs(ans['mse_a'] - mse_a) < 1e-3, f"MSE_A is incorrect. Expected ~{mse_a:.4f}, got {ans['mse_a']}"
    assert abs(ans['mse_b'] - mse_b) < 1e-3, f"MSE_B is incorrect. Expected ~{mse_b:.4f}, got {ans['mse_b']}"
    assert abs(ans['t_stat'] - t_stat) < 1e-3, f"t_stat is incorrect. Expected ~{t_stat:.4f}, got {ans['t_stat']}"
    assert ans['is_significant'] == expected_is_significant, f"is_significant is incorrect. Expected {expected_is_significant}, got {ans['is_significant']}"
TEST_EOF

run_checks() {
    [ -f /home/user/evaluate.go ] || return 1
    [ ! -L /home/user/evaluate.go ] || return 1

    local nonstandard
    nonstandard=$(cd /home/user && GO111MODULE=off go list -deps -f '{{if and (not .Standard) (ne .ImportPath "command-line-arguments")}}{{.ImportPath}}{{end}}' evaluate.go) || return 1
    [ -z "$(printf '%s' "$nonstandard" | tr -d '[:space:]')" ] || return 1

    GO111MODULE=off go build -o /tmp/evaluate_submission /home/user/evaluate.go || return 1
    rm -f /home/user/report.json || return 1
    runuser -u user -- timeout 30s /tmp/evaluate_submission || return 1

    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1 || return 1
}

if run_checks; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
