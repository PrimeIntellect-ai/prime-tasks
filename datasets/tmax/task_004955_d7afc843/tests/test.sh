#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import numpy as np
import pandas as pd
import pytest

def test_variance_output_mse():
    # 1. Compute truth variance
    video_path = '/app/sensor_feed.mp4'
    assert os.path.exists(video_path), f"Video file missing: {video_path}"

    # We use cv2 to match the exact tracking logic in the original script
    try:
        import cv2
    except ImportError:
        pytest.fail("cv2 is not installed, cannot compute ground truth.")

    cap = cv2.VideoCapture(video_path)
    x_coords = []
    offset = 1000000.0  # The active offset from the database

    while cap.isOpened():
        ret, frame = cap.read()
        if not ret:
            break
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        _, _, _, max_loc = cv2.minMaxLoc(gray)
        x_coords.append(max_loc[0] + offset)

    cap.release()

    x_coords = np.array(x_coords, dtype=np.float64)
    window = 30
    truth_variances = []
    for i in range(window - 1, len(x_coords)):
        window_data = x_coords[i - window + 1 : i + 1]
        var = np.var(window_data, ddof=0, dtype=np.float64)
        truth_variances.append((i, var))

    truth_df = pd.DataFrame(truth_variances, columns=['frame_idx', 'variance_true'])

    # 2. Load agent output
    agent_output_path = '/home/user/variance_output.csv'
    assert os.path.exists(agent_output_path), f"Agent output missing at {agent_output_path}"

    agent_df = pd.read_csv(agent_output_path)
    assert 'frame_idx' in agent_df.columns and 'variance' in agent_df.columns, "Output CSV must have 'frame_idx' and 'variance' columns"

    # 3. Merge and compute MSE
    merged = pd.merge(truth_df, agent_df, on='frame_idx', suffixes=('_true', '_agent'))
    assert len(merged) > 0, "No overlapping frame indices found between truth and agent output."
    assert len(merged) == len(truth_df), "Agent output does not contain all expected frames."

    mse = np.mean((merged['variance_true'] - merged['variance'])**2)

    threshold = 1e-5
    assert mse <= threshold, f"MSE {mse} exceeds threshold {threshold}. The variance calculation is still numerically unstable or using the wrong calibration offset."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
