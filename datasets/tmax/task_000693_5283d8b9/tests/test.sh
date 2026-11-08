#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import math
import pytest

def test_analysis_out_exists_and_correct():
    out_file = "/home/user/analysis_out.json"
    assert os.path.isfile(out_file), f"Output file {out_file} does not exist."

    with open(out_file, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {out_file} is not valid JSON.")

    expected_keys = {"shortest_path", "path_length", "js_distance", "is_distorted"}
    assert set(data.keys()) == expected_keys, f"JSON keys must be exactly {expected_keys}, found {set(data.keys())}."

    # Recompute expected shortest path and length
    expected_path = ["N_0", "N_1", "N_2", "N_3"]
    expected_length = 2.9

    assert data["shortest_path"] == expected_path, f"Expected shortest_path {expected_path}, got {data['shortest_path']}."
    assert math.isclose(data["path_length"], expected_length, abs_tol=1e-4), f"Expected path_length {expected_length}, got {data['path_length']}."

    # Recompute JSD
    # N_0 = [1, 2, 1, 0]
    # N_3 = [2, 0, -2, 0]

    # N_0 FFT mag^2 normalized: [2/3, 1/6, 0, 1/6]
    p = [2/3, 1/6, 0.0, 1/6]
    # N_3 FFT mag^2 normalized: [0, 1/2, 0, 1/2]
    q = [0.0, 1/2, 0.0, 1/2]

    # M = (P + Q) / 2
    m = [(p_i + q_i) / 2 for p_i, q_i in zip(p, q)]

    # KL(P||M)
    kl_pm = sum(p_i * math.log(p_i / m_i) for p_i, m_i in zip(p, m) if p_i > 0)
    # KL(Q||M)
    kl_qm = sum(q_i * math.log(q_i / m_i) for q_i, m_i in zip(q, m) if q_i > 0)

    jsd = math.sqrt((kl_pm + kl_qm) / 2)
    expected_jsd = round(jsd, 4)
    expected_is_distorted = expected_jsd > 0.5

    assert math.isclose(data["js_distance"], expected_jsd, abs_tol=1e-4), f"Expected js_distance {expected_jsd}, got {data['js_distance']}."
    assert data["is_distorted"] == expected_is_distorted, f"Expected is_distorted to be {expected_is_distorted}, got {data['is_distorted']}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
