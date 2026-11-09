#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import subprocess
import tempfile
import math
import pandas as pd
import numpy as np
from PIL import Image

AGENT_CSV = "/home/user/final_output.csv"
VIDEO_PATH = "/app/experiment.mp4"

def calculate_true_entropy(probabilities):
    entropy = 0.0
    for p in probabilities:
        if p > 0:
            entropy -= p * math.log(p, 2)
    return entropy

def test_final_output_exists_and_format():
    assert os.path.exists(AGENT_CSV), f"Expected output file {AGENT_CSV} does not exist."

    df = pd.read_csv(AGENT_CSV)
    assert "frame_index" in df.columns, "Output CSV missing 'frame_index' column."
    assert "entropy" in df.columns, "Output CSV missing 'entropy' column."
    assert len(df.columns) == 2, "Output CSV should only have 'frame_index' and 'entropy' columns."

def test_entropy_accuracy():
    assert os.path.exists(AGENT_CSV), f"Expected output file {AGENT_CSV} does not exist."

    # Extract frames to a temporary directory to compute ground truth
    with tempfile.TemporaryDirectory() as temp_dir:
        subprocess.run(
            ["ffmpeg", "-i", VIDEO_PATH, "-vf", "format=gray", f"{temp_dir}/frame_%04d.png"],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL
        )

        frames = [f for f in os.listdir(temp_dir) if f.endswith('.png')]
        assert len(frames) > 0, "No frames extracted from video."

        truth_data = []
        for frame_file in frames:
            frame_idx = int(frame_file.split('_')[1].split('.')[0])
            filepath = os.path.join(temp_dir, frame_file)

            img = Image.open(filepath)
            histogram = img.histogram()
            total_pixels = sum(histogram)
            probabilities = [count / total_pixels for count in histogram]

            entropy = calculate_true_entropy(probabilities)
            truth_data.append({"frame_index": frame_idx, "entropy": entropy})

    truth_df = pd.DataFrame(truth_data)
    agent_df = pd.read_csv(AGENT_CSV)

    # Ensure all frames are present and sorted
    agent_df = agent_df.sort_values(by="frame_index").reset_index(drop=True)
    truth_df = truth_df.sort_values(by="frame_index").reset_index(drop=True)

    assert len(agent_df) == len(truth_df), f"Row count mismatch: Expected {len(truth_df)}, got {len(agent_df)}"

    # Check that frame indices match exactly
    np.testing.assert_array_equal(
        agent_df["frame_index"].values, 
        truth_df["frame_index"].values, 
        err_msg="Frame indices in the output do not match the expected sequence."
    )

    mse = np.mean((agent_df['entropy'] - truth_df['entropy'])**2)
    threshold = 1e-4

    assert mse < threshold, f"MSE exceeds threshold. Expected < {threshold}, got {mse}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
