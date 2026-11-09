#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import pytest

def test_flagged_json_f1_score():
    ground_truth_path = "/tests/ground_truth.json"
    flagged_path = "/home/user/flagged.json"

    assert os.path.exists(ground_truth_path), f"Ground truth file {ground_truth_path} is missing."
    assert os.path.exists(flagged_path), f"Output file {flagged_path} is missing."

    try:
        with open(ground_truth_path, "r") as f:
            truth = set(json.load(f))
    except Exception as e:
        pytest.fail(f"Failed to load ground truth: {e}")

    try:
        with open(flagged_path, "r") as f:
            pred_data = json.load(f)
            assert isinstance(pred_data, list), "flagged.json must contain a list of filenames."
            pred = set(pred_data)
    except Exception as e:
        pytest.fail(f"Failed to load flagged.json: {e}")

    tp = len(truth & pred)
    fp = len(pred - truth)
    fn = len(truth - pred)

    if tp == 0:
        f1 = 0.0
    else:
        precision = tp / (tp + fp)
        recall = tp / (tp + fn)
        f1 = 2 * (precision * recall) / (precision + recall)

    threshold = 0.95
    assert f1 >= threshold, f"F1 Score {f1:.4f} is below the threshold of {threshold}. TP:{tp}, FP:{fp}, FN:{fn}"

def test_block_sh_exists_and_format():
    block_sh_path = "/home/user/block.sh"
    assert os.path.exists(block_sh_path), f"Firewall script {block_sh_path} is missing."

    with open(block_sh_path, "r") as f:
        lines = f.readlines()

    assert len(lines) > 0, f"{block_sh_path} is empty."

    for line in lines:
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        assert line.startswith("iptables -A OUTPUT -d "), f"Invalid iptables command format in {block_sh_path}: {line}"
        assert line.endswith(" -j DROP"), f"Invalid iptables command format in {block_sh_path}: {line}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
