#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import random
import subprocess
import numpy as np
import matplotlib.image as mpimg
import pytest


def test_plot_exists():
    """Verify that the requested plot was generated and is a valid, non-empty PNG."""
    plot_path = "/home/user/plot.png"
    assert os.path.isfile(plot_path), f"The plot file {plot_path} was not generated."
    assert os.path.getsize(plot_path) > 0, f"The plot file {plot_path} is empty."
    with open(plot_path, "rb") as f:
        assert f.read(8) == b"\x89PNG\r\n\x1a\n", f"The plot file {plot_path} is not a PNG."
    image = mpimg.imread(plot_path)
    assert image.ndim in (2, 3) and image.shape[0] > 1 and image.shape[1] > 1, "The plot has invalid dimensions."
    assert np.ptp(image.astype(float)) > 0, "The plot contains no visible variation."


def test_fuzz_equivalence():
    """Fuzz the agent script against the oracle script to verify bit-exact equivalence."""
    oracle_path = "/tests/oracle.py"
    agent_path = "/home/user/simulate.py"

    assert os.path.isfile(agent_path), f"Agent script not found at {agent_path}"
    assert os.path.isfile(oracle_path), f"Oracle script not found at {oracle_path}"

    random.seed(42)
    charset = "ACDEFGHIKLMNPQRSTVWY"

    for _ in range(200):
        length = random.randint(10, 100)
        seq = "".join(random.choice(charset) for _ in range(length))

        oracle_cmd = ["python3", oracle_path, seq]
        oracle_res = subprocess.run(oracle_cmd, capture_output=True, text=True)
        assert oracle_res.returncode == 0, f"Oracle failed on input {seq}. Stderr: {oracle_res.stderr}"
        oracle_out = oracle_res.stdout.strip()

        agent_cmd = ["python3", agent_path, seq]
        agent_res = subprocess.run(agent_cmd, capture_output=True, text=True)
        assert agent_res.returncode == 0, f"Agent script failed on input {seq}. Stderr: {agent_res.stderr}"
        agent_out = agent_res.stdout.strip()

        assert agent_out == oracle_out, (
            f"Mismatch on input {seq}.\n"
            f"Oracle output: {oracle_out}\n"
            f"Agent output: {agent_out}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
