#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import gzip
import numpy as np
import pytest

def test_artifact_payload_extraction_and_compression():
    original_file = '/app/artifact_raw.wav'
    agent_file = '/home/user/artifact_payload.gz'

    # Ensure the original file exists
    assert os.path.exists(original_file), f"Original file {original_file} is missing."

    # Ensure the agent's output file exists
    assert os.path.exists(agent_file), f"Agent's output file {agent_file} is missing."

    # Read original data (skipping 44-byte header)
    with open(original_file, 'rb') as f:
        f.seek(44)
        original_bytes = f.read()

    # Read agent's compressed payload
    try:
        with gzip.open(agent_file, 'rb') as f:
            agent_bytes = f.read()
    except gzip.BadGzipFile:
        pytest.fail(f"The file {agent_file} is not a valid gzip archive.")

    original_samples = np.frombuffer(original_bytes, dtype=np.int16)
    agent_samples = np.frombuffer(agent_bytes, dtype=np.int16)

    # Calculate MSE
    if len(original_samples) != len(agent_samples):
        pytest.fail(f"Sample count mismatch: Original has {len(original_samples)} samples, Agent has {len(agent_samples)} samples.")

    mse = np.mean((original_samples.astype(np.float64) - agent_samples.astype(np.float64))**2)

    assert mse <= 0.0, f"MSE is {mse}, but expected 0.0. The extracted payload does not perfectly match the original data chunk."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
