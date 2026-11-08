#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import json
import os
import pytest

def calculate_iou(boxA, boxB):
    xA = max(boxA[0], boxB[0])
    yA = max(boxA[1], boxB[1])
    xB = min(boxA[0] + boxA[2], boxB[0] + boxB[2])
    yB = min(boxA[1] + boxA[3], boxB[1] + boxB[3])

    interArea = max(0, xB - xA) * max(0, yB - yA)
    boxAArea = boxA[2] * boxA[3]
    boxBArea = boxB[2] * boxB[3]

    denominator = float(boxAArea + boxBArea - interArea)
    if denominator == 0:
        return 0.0
    return interArea / denominator

def test_regression_test_exists():
    test_path = "/home/user/tracker/test_tracker.py"
    assert os.path.exists(test_path), f"Regression test script missing at {test_path}. You must create it."
    with open(test_path, "r") as f:
        content = f.read()
    assert "def test_" in content or "class Test" in content, "No pytest or unittest test found in test_tracker.py"

def test_output_iou():
    output_path = "/home/user/tracker/output.json"
    gt_path = "/tests/ground_truth.json"

    assert os.path.exists(output_path), f"Output file missing at {output_path}. Did you run the fixed script?"

    with open(gt_path, 'r') as f:
        gt = json.load(f)

    try:
        with open(output_path, 'r') as f:
            pred = json.load(f)
    except Exception as e:
        pytest.fail(f"Error reading prediction JSON at {output_path}: {e}")

    assert isinstance(pred, list), f"Output must be a list of lists, got {type(pred)}"
    assert len(gt) == len(pred), f"Frame count mismatch. Expected {len(gt)} frames, got {len(pred)} frames in output.json"

    ious = [calculate_iou(g, p) for g, p in zip(gt, pred)]
    avg_iou = sum(ious) / len(ious)

    assert avg_iou >= 0.85, f"Average IoU too low: {avg_iou:.4f} < 0.85. The tracking algorithm is not accurate enough or fails to interpolate corrupted frames properly."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
