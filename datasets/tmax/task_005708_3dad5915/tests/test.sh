#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import math

def test_report_json():
    report_path = "/home/user/report.json"
    assert os.path.exists(report_path), f"Report file {report_path} is missing."
    assert os.path.isfile(report_path), f"Report path {report_path} is not a file."

    with open(report_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"File {report_path} is not valid JSON."

    expected_keys = {"pc1_variance_ratio", "t_statistic", "p_value", "reject_null"}
    actual_keys = set(data.keys())
    assert expected_keys.issubset(actual_keys), f"Missing keys in report.json. Expected {expected_keys}, got {actual_keys}"

    expected_var = 0.029837922756627606
    expected_t = 1.4656912304910355
    expected_p = 0.14429997184497645

    assert isinstance(data['pc1_variance_ratio'], float), "pc1_variance_ratio must be a float."
    assert isinstance(data['t_statistic'], float), "t_statistic must be a float."
    assert isinstance(data['p_value'], float), "p_value must be a float."
    assert isinstance(data['reject_null'], bool), "reject_null must be a boolean."

    assert math.isclose(data['pc1_variance_ratio'], expected_var, rel_tol=1e-3), f"Variance ratio mismatch: {data['pc1_variance_ratio']} != {expected_var}"
    assert math.isclose(abs(data['t_statistic']), abs(expected_t), rel_tol=1e-3), f"t_statistic mismatch: {data['t_statistic']} != {expected_t}"
    assert math.isclose(data['p_value'], expected_p, rel_tol=1e-3), f"p_value mismatch: {data['p_value']} != {expected_p}"
    assert data['reject_null'] is False, f"reject_null should be False, but got {data['reject_null']}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
