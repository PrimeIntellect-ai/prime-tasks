#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import subprocess
import tempfile
import pytest

ORACLE_SCRIPT = "/tests/oracle.sh"
AGENT_SCRIPT = "/home/user/pipeline.sh"
NUM_FUZZ_TESTS = 10

def generate_fuzz_video(path, duration):
    """Generate a random video using ffmpeg testsrc filter."""
    cmd = [
        "ffmpeg",
        "-f", "lavfi",
        "-i", f"testsrc=duration={duration}:rate=30",
        "-y",
        path
    ]
    subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)

def test_pipeline_fuzz_equivalence():
    """Fuzz equivalence test comparing the agent's script to the oracle."""
    assert os.path.exists(AGENT_SCRIPT), f"Agent script not found at {AGENT_SCRIPT}"
    assert os.path.exists(ORACLE_SCRIPT), f"Oracle script not found at {ORACLE_SCRIPT}"

    random.seed(42)

    with tempfile.TemporaryDirectory() as temp_dir:
        cases = []
        for i in range(NUM_FUZZ_TESTS):
            duration = random.randint(2, 15)
            video_path = os.path.join(temp_dir, f"fuzz_in_{i}.mp4")
            generate_fuzz_video(video_path, duration)

            oracle_cmd = ["bash", ORACLE_SCRIPT, video_path]
            oracle_result = subprocess.run(oracle_cmd, capture_output=True, text=True)
            assert oracle_result.returncode == 0, f"Oracle script failed on fuzz input {i} (duration={duration})"
            cases.append((i, duration, video_path, oracle_result.stdout.strip()))

        # Remove the uploaded oracle before executing any agent-controlled code.
        os.remove(ORACLE_SCRIPT)

        for i, duration, video_path, oracle_output in cases:
            agent_cmd = ["bash", AGENT_SCRIPT, video_path]
            agent_result = subprocess.run(agent_cmd, capture_output=True, text=True)
            assert agent_result.returncode == 0, f"Agent script failed on fuzz input {i} (duration={duration}). Error: {agent_result.stderr}"
            agent_output = agent_result.stdout.strip()

            assert agent_output == oracle_output, (
                f"Mismatch on fuzz input {i} (duration={duration}s).\n"
                f"Oracle output:\n{oracle_output}\n"
                f"Agent output:\n{agent_output}\n"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
