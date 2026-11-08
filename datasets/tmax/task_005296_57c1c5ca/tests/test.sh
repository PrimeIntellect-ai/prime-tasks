#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import subprocess
import pytest

def test_anomaly_frame_index():
    anomaly_file = "/home/user/anomaly_frame.txt"
    assert os.path.isfile(anomaly_file), f"Missing anomaly frame file at {anomaly_file}"

    with open(anomaly_file, "r") as f:
        content = f.read().strip()

    # Full-frame analysis finds original frame 46. Ordinary 1 fps extraction,
    # which the instruction explicitly permits, skips that one-frame anomaly;
    # all sampled frames tie and conventional first-maximum selection yields 0.
    assert content in {"0", "46"}, (
        f"Expected anomaly frame index to be '46' for all-frame analysis or '0' "
        f"for permitted 1 fps sampling, but got '{content}'"
    )

def test_event_parser_fuzz_equivalence():
    oracle_path = "/app/legacy_parser"
    agent_path = "/home/user/event_parser"

    assert os.path.isfile(oracle_path), f"Missing oracle program at {oracle_path}"
    assert os.access(oracle_path, os.X_OK), f"Oracle program at {oracle_path} is not executable"

    assert os.path.isfile(agent_path), f"Missing agent program at {agent_path}"
    assert os.access(agent_path, os.X_OK), f"Agent program at {agent_path} is not executable"

    random.seed(42)
    hex_chars = "0123456789abcdefABCDEF"

    for i in range(1000):
        length = random.randint(8, 64)
        test_input = "".join(random.choice(hex_chars) for _ in range(length))

        try:
            oracle_result = subprocess.run(
                [oracle_path, test_input],
                capture_output=True,
                text=True,
                check=True,
                timeout=2
            )
            oracle_stdout = oracle_result.stdout
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Oracle program failed on input '{test_input}' with error: {e.stderr}")
        except subprocess.TimeoutExpired:
            pytest.fail(f"Oracle program timed out on input '{test_input}'")

        try:
            agent_result = subprocess.run(
                [agent_path, test_input],
                capture_output=True,
                text=True,
                check=True,
                timeout=2
            )
            agent_stdout = agent_result.stdout
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Agent program failed on input '{test_input}' with error: {e.stderr}")
        except subprocess.TimeoutExpired:
            pytest.fail(f"Agent program timed out on input '{test_input}'")

        assert agent_stdout == oracle_stdout, (
            f"Output mismatch on input '{test_input}'.\n"
            f"Expected (oracle): {repr(oracle_stdout)}\n"
            f"Got (agent): {repr(agent_stdout)}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
