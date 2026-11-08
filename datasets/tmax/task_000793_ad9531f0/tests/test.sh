#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import random
import string
import tempfile
import pytest

ORACLE_PATH = "/tests/reference_oracle.py"
AGENT_PATH = "/app/video_processor_fixed.py"
N_FUZZ = 20

def generate_random_video(path, num_frames):
    # Generate a fast test video using ffmpeg
    cmd = [
        "ffmpeg", "-y", "-f", "lavfi", "-i", f"testsrc=s=64x64:d={num_frames/30.0}:r=30",
        "-c:v", "libx264", "-frames:v", str(num_frames),
        path
    ]
    subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)

def test_fuzz_equivalence():
    assert os.path.exists(AGENT_PATH), f"Agent script {AGENT_PATH} not found. Ensure you saved the fixed script to the correct path."
    assert os.path.exists(ORACLE_PATH), f"Oracle script {ORACLE_PATH} not found."

    random.seed(42)

    with tempfile.TemporaryDirectory() as tmpdir:
        for i in range(N_FUZZ):
            num_frames = random.randint(1, 150) # Use up to 150 frames to keep tests fast but robust

            # Generate tricky filename with spaces and special characters
            name_chars = string.ascii_letters + string.digits + " '"
            filename = "".join(random.choices(name_chars, k=10)) + f" test vid {i}.mp4"
            video_path = os.path.join(tmpdir, filename)

            generate_random_video(video_path, num_frames)

            oracle_out = os.path.join(tmpdir, f"oracle_{i}.bin")
            agent_out = os.path.join(tmpdir, f"agent_{i}.bin")

            # Run oracle
            try:
                subprocess.run(["python3", ORACLE_PATH, video_path, oracle_out], check=True, capture_output=True)
            except subprocess.CalledProcessError as e:
                pytest.fail(f"Oracle failed to process {video_path}: {e.stderr}")

            # Run agent
            res = subprocess.run(["python3", AGENT_PATH, video_path, agent_out], capture_output=True, text=True)
            assert res.returncode == 0, f"Agent script failed on input '{filename}'.\nStderr: {res.stderr}"

            assert os.path.exists(agent_out), f"Agent script did not produce output file {agent_out} for '{filename}'."

            with open(oracle_out, "rb") as f:
                oracle_data = f.read()
            with open(agent_out, "rb") as f:
                agent_data = f.read()

            if oracle_data != agent_data:
                pytest.fail(f"Output mismatch on video '{filename}' ({num_frames} frames).\n"
                            f"Expected {len(oracle_data)} bytes, got {len(agent_data)} bytes.\n"
                            f"Ensure you are extracting and computing the mean intensity correctly without storing all frames.")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
