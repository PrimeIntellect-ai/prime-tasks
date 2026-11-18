#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import subprocess
import pytest

AGENT_SCRIPT = "/home/user/process_stream.sh"
ORACLE_SCRIPT = "/tests/oracle.sh"

def test_script_exists_and_executable():
    """Verify the agent's script exists and is executable."""
    assert os.path.exists(AGENT_SCRIPT), f"Agent script {AGENT_SCRIPT} does not exist."
    assert os.path.isfile(AGENT_SCRIPT), f"{AGENT_SCRIPT} is not a file."
    assert os.access(AGENT_SCRIPT, os.X_OK), f"Agent script {AGENT_SCRIPT} is not executable."

def generate_random_input(seed):
    """Generate a random input for the streaming process."""
    random.seed(seed)
    num_lines = random.randint(5, 15)
    lines = []
    for _ in range(num_lines):
        event_id = random.randint(1, 10000)
        timestamp = f"00:00:0{random.randint(0, 9)}"
        lines.append(f"{event_id} {timestamp}")
    return "\n".join(lines) + "\n"

@pytest.mark.parametrize("seed", range(10))
def test_fuzz_equivalence(seed):
    """Compare the agent's script against the oracle script on random inputs."""
    input_data = generate_random_input(seed)

    oracle_proc = subprocess.run(
        [ORACLE_SCRIPT],
        input=input_data,
        text=True,
        capture_output=True
    )
    assert oracle_proc.returncode == 0, f"Oracle failed with error: {oracle_proc.stderr}"

    agent_proc = subprocess.run(
        [AGENT_SCRIPT],
        input=input_data,
        text=True,
        capture_output=True
    )

    if agent_proc.returncode != 0:
        pytest.fail(f"Agent script failed with error: {agent_proc.stderr}\nInput was:\n{input_data}")

    oracle_output = oracle_proc.stdout.strip()
    agent_output = agent_proc.stdout.strip()

    if oracle_output != agent_output:
        pytest.fail(
            f"Output mismatch for seed {seed}.\n"
            f"Input:\n{input_data}\n"
            f"Expected (Oracle):\n{oracle_output}\n\n"
            f"Got (Agent):\n{agent_output}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
