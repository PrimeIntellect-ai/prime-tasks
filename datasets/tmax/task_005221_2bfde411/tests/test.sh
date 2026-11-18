#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import pytest

def compute_ground_truth(file_path):
    with open(file_path, 'r') as f:
        lines = f.readlines()[1:]

    valid_scores = []
    best_score = -1
    best_seq = ""

    for line in lines:
        parts = line.strip().split('\t')
        if len(parts) != 4:
            continue
        iteration = int(parts[0])
        seq = parts[1]
        score = int(parts[2])
        accepted = int(parts[3])

        if iteration > 500 and accepted == 1:
            valid_scores.append(score)
            if score > best_score:
                best_score = score
                best_seq = seq

    bins = [0]*5
    for s in valid_scores:
        if 0 <= s < 20: bins[0] += 1
        elif 20 <= s < 40: bins[1] += 1
        elif 40 <= s < 60: bins[2] += 1
        elif 60 <= s < 80: bins[3] += 1
        elif 80 <= s <= 100: bins[4] += 1

    total = len(valid_scores)
    if total == 0:
        return 0.0, ""

    tvd = 0.5 * sum(abs((b/total) - 0.2) for b in bins)

    return round(tvd, 4), best_seq[:10]

def test_analysis_summary():
    json_path = "/home/user/analysis_summary.json"
    data_path = "/home/user/mcmc_results.tsv"

    assert os.path.exists(data_path), f"Input data file {data_path} is missing."

    assert os.path.exists(json_path), f"Output file {json_path} does not exist. Did you create it?"
    assert os.path.isfile(json_path), f"Path {json_path} is not a valid file."

    with open(json_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {json_path} does not contain valid JSON.")

    assert "tvd" in data, "Key 'tvd' is missing from the JSON output."
    assert "primer" in data, "Key 'primer' is missing from the JSON output."

    expected_tvd, expected_primer = compute_ground_truth(data_path)

    assert isinstance(data["tvd"], (int, float)), "Value for 'tvd' must be a numeric type."
    assert round(data["tvd"], 4) == expected_tvd, f"Incorrect tvd value. Expected {expected_tvd}, but got {data['tvd']}."

    assert data["primer"] == expected_primer, f"Incorrect primer sequence. Expected '{expected_primer}', but got '{data['primer']}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
