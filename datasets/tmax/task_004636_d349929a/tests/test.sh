#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import pandas as pd
import numpy as np
import cv2
import torch
import torch.nn as nn
import pytest

def get_reference_scores():
    cap = cv2.VideoCapture('/app/noisy_feed.mp4')
    frames = []
    while True:
        ret, frame = cap.read()
        if not ret:
            break
        # OpenCV reads as BGR even if written as grayscale, so convert back
        if len(frame.shape) == 3:
            frame = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        frames.append(frame.astype(np.float32))
    cap.release()

    frames = np.array(frames)
    median_frame = np.median(frames, axis=0)
    cleaned = frames - median_frame

    N, H, W = cleaned.shape
    flattened = cleaned.reshape(N, -1)

    np.random.seed(42)
    P = np.random.randn(W * H, 10).astype(np.float32)

    features = np.dot(flattened, P)

    net = nn.Sequential(
        nn.Linear(10, 16),
        nn.ReLU(),
        nn.Linear(16, 1)
    )
    net.load_state_dict(torch.load('/app/model.pth'))
    net.eval()

    with torch.no_grad():
        scores = net(torch.tensor(features, dtype=torch.float32)).numpy().flatten()
    return scores

def test_anomaly_scores_accuracy():
    csv_path = '/home/user/anomaly_scores.csv'
    assert os.path.exists(csv_path), f"Output file missing: {csv_path}"

    try:
        agent_df = pd.read_csv(csv_path)
    except Exception as e:
        pytest.fail(f"Failed to read CSV file: {e}")

    assert 'frame_idx' in agent_df.columns, "Missing 'frame_idx' column in CSV"
    assert 'score' in agent_df.columns, "Missing 'score' column in CSV"

    agent_scores = agent_df['score'].values
    ref_scores = get_reference_scores()

    assert len(agent_scores) == len(ref_scores), f"Length mismatch: agent has {len(agent_scores)} frames, expected {len(ref_scores)}"

    mae = np.max(np.abs(agent_scores - ref_scores))
    assert mae <= 0.01, f"Maximum Absolute Error {mae} exceeds threshold 0.01"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
