#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import json
import os
import subprocess
import tempfile
import glob
import numpy as np
import pytest

def test_output_json_valid_and_correct():
    output_path = "/home/user/output.json"
    assert os.path.isfile(output_path), f"{output_path} does not exist. Did you run the pipeline?"

    try:
        with open(output_path, "r") as f:
            data = json.load(f)
    except json.JSONDecodeError as e:
        pytest.fail(f"Output is not valid JSON: {e}")

    assert "title" in data, "JSON missing 'title' key."
    assert "frame_thresholds" in data, "JSON missing 'frame_thresholds' key."

    expected_title = r'Test "Video" \ Data'
    assert data["title"] == expected_title, f"Title is incorrect. Expected: {expected_title}, Got: {data['title']}"

    agent_arr = np.array(data["frame_thresholds"], dtype=float)

    # Re-derive the golden reference by running the same extraction and mean calculation
    with tempfile.TemporaryDirectory() as tmpdir:
        subprocess.run(
            ["ffmpeg", "-i", "/app/video.mp4", "-vf", "format=gray", os.path.join(tmpdir, "frame_%04d.jpg")],
            stdout=subprocess.DEVNULL, 
            stderr=subprocess.DEVNULL, 
            check=True
        )

        frames = sorted(glob.glob(os.path.join(tmpdir, "*.jpg")))
        assert len(frames) > 0, "Failed to extract frames from video for ground truth calculation."

        golden = []
        for f in frames:
            res = subprocess.run(
                ["convert", f, "-format", "%[fx:mean*255]", "info:"], 
                capture_output=True, 
                text=True, 
                check=True
            )
            golden.append(float(res.stdout.strip()))

    golden_arr = np.array(golden, dtype=float)

    assert len(agent_arr) == len(golden_arr), f"Expected {len(golden_arr)} thresholds, got {len(agent_arr)}"

    mse = np.mean((agent_arr - golden_arr)**2)
    assert mse <= 0.05, f"MSE of frame_thresholds is {mse:.4f}, which is > 0.05 threshold."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
