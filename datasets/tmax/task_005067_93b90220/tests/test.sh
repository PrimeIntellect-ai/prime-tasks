#!/bin/bash
set -e
mkdir -p /logs/verifier
chmod +x /tests/oracle_tokenizer

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import subprocess
import random
import pytest

def test_fuzz_equivalence():
    """Fuzz the agent's Go binary against the oracle with random byte streams."""
    agent_bin = "/home/user/video_tokenizer"
    oracle_bin = "/tests/oracle_tokenizer"

    assert os.path.exists(agent_bin), f"Agent binary not found at {agent_bin}"
    assert os.access(agent_bin, os.X_OK), f"Agent binary at {agent_bin} is not executable"

    random.seed(42)
    for i in range(100):
        length = random.randint(0, 1000000)
        input_data = random.randbytes(length)

        oracle_proc = subprocess.run([oracle_bin], input=input_data, capture_output=True)
        agent_proc = subprocess.run([agent_bin], input=input_data, capture_output=True)

        assert agent_proc.stdout == oracle_proc.stdout, (
            f"Output mismatch on fuzz iteration {i} with input length {length}. "
            f"Oracle produced {len(oracle_proc.stdout)} bytes, agent produced {len(agent_proc.stdout)} bytes."
        )

def test_pipeline_output_matches_oracle():
    """Verify that the final dataset.bin matches the exact output of the oracle pipeline."""
    dataset_path = "/home/user/dataset.bin"
    assert os.path.exists(dataset_path), f"Final dataset not found at {dataset_path}"

    # Reconstruct the expected output using the oracle
    ffmpeg_cmd = [
        "ffmpeg", "-loglevel", "error",
        "-i", "/app/training_source.mp4",
        "-r", "5",
        "-s", "320x240",
        "-f", "rawvideo",
        "-pix_fmt", "rgb24",
        "-"
    ]
    ffmpeg_proc = subprocess.run(ffmpeg_cmd, capture_output=True, check=True)

    oracle_proc = subprocess.run(["/tests/oracle_tokenizer"], input=ffmpeg_proc.stdout, capture_output=True)
    expected_output = oracle_proc.stdout

    with open(dataset_path, "rb") as f:
        actual_output = f.read()

    assert actual_output == expected_output, (
        f"dataset.bin content does not match expected oracle output. "
        f"Expected {len(expected_output)} bytes, got {len(actual_output)} bytes."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
