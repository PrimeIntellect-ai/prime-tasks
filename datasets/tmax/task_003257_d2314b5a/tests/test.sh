#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import sys
import random
import string
import subprocess
import pytest

def test_part1_video_analysis():
    """Check if the user correctly identified the failed frames for Node-3."""
    expected_frames = {'450', '451', '452', '900', '901', '902'}
    file_path = "/home/user/failed_nodes.txt"

    assert os.path.isfile(file_path), f"File not found: {file_path}"

    with open(file_path, "r") as f:
        lines = f.read().strip().splitlines()

    actual_frames = {line.strip() for line in lines if line.strip()}
    assert actual_frames == expected_frames, f"Expected frames {expected_frames}, but got {actual_frames} in {file_path}"

def generate_fuzz_string():
    """Generates a random log string with injected keywords and IPs."""
    length = random.randint(0, 2048)
    chars = string.ascii_letters + string.digits + " \n\t.,;:!?"
    base_str = "".join(random.choices(chars, k=length))

    # Inject some phrases that are relevant to the parsing logic
    phrases = [
        "Connection closed by ",
        "Disconnecting from ",
        "publickey",
        "192.168.1.1",
        "10.0.0.256",
        "255.255.255.255",
        "999.999.999.999",
        "1.2.3",
        "1.2.3.4.5"
    ]

    num_injects = random.randint(0, 15)
    for _ in range(num_injects):
        phrase = random.choice(phrases)
        if len(base_str) == 0:
            base_str = phrase
        else:
            insert_pos = random.randint(0, len(base_str))
            base_str = base_str[:insert_pos] + phrase + base_str[insert_pos:]

    return base_str[:2048]

def test_part2_log_analyzer_fuzzing():
    """Fuzz test the user's log parsing script against the oracle."""
    agent_script = "/home/user/parse_deployment_logs.py"
    oracle_script = "/tests/oracle_log_parser.py"

    assert os.path.isfile(agent_script), f"Agent script missing at {agent_script}"
    assert os.path.isfile(oracle_script), f"Oracle script missing at {oracle_script}"

    random.seed(42)
    N = 5000

    for i in range(N):
        fuzz_input = generate_fuzz_string()

        # Run oracle
        oracle_proc = subprocess.run(
            [sys.executable, oracle_script, fuzz_input],
            capture_output=True, text=True
        )

        # Run agent
        agent_proc = subprocess.run(
            [sys.executable, agent_script, fuzz_input],
            capture_output=True, text=True
        )

        # Check return codes
        assert agent_proc.returncode == oracle_proc.returncode, (
            f"Return code mismatch on fuzz iteration {i}.\n"
            f"Input: {repr(fuzz_input)}\n"
            f"Oracle return code: {oracle_proc.returncode}\n"
            f"Agent return code: {agent_proc.returncode}\n"
            f"Agent stderr: {agent_proc.stderr}"
        )

        # Check stdout match
        assert agent_proc.stdout == oracle_proc.stdout, (
            f"Output mismatch on fuzz iteration {i}.\n"
            f"Input: {repr(fuzz_input)}\n"
            f"Oracle stdout: {repr(oracle_proc.stdout)}\n"
            f"Agent stdout: {repr(agent_proc.stdout)}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
