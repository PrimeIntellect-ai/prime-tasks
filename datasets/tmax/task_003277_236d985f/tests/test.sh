#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import subprocess
import pytest

def test_fuzz_equivalence():
    """
    Fuzz-equivalence test comparing the agent's script against the reference oracle.
    """
    agent_script = '/home/user/find_similar_frame.py'
    oracle_script = '/tests/oracle_embedder.py'
    video_path = '/app/raw_footage.mp4'
    n_frames = '50'
    num_iterations = 20

    assert os.path.exists(agent_script), f"Agent script {agent_script} does not exist."
    assert os.path.exists(oracle_script), f"Oracle script {oracle_script} does not exist."

    random.seed(1337)

    for i in range(num_iterations):
        # Generate random 16-dimensional target embedding
        embedding = [random.uniform(-1.0, 1.0) for _ in range(16)]
        embedding_str = ','.join(f"{x:.6f}" for x in embedding)

        # Run oracle
        oracle_cmd = ['python3', oracle_script, video_path, n_frames, embedding_str]
        oracle_res = subprocess.run(oracle_cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        assert oracle_res.returncode == 0, f"Oracle failed on iteration {i}:\n{oracle_res.stderr}"
        oracle_output = oracle_res.stdout.strip()

        # Run agent
        agent_cmd = ['python3', agent_script, video_path, n_frames, embedding_str]
        agent_res = subprocess.run(agent_cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        assert agent_res.returncode == 0, f"Agent script failed on iteration {i}:\n{agent_res.stderr}"
        agent_output = agent_res.stdout.strip()

        assert agent_output == oracle_output, (
            f"Output mismatch on iteration {i}.\n"
            f"Input embedding: {embedding_str}\n"
            f"Expected (Oracle): {oracle_output}\n"
            f"Actual (Agent): {agent_output}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
