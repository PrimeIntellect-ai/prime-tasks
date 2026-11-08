#!/bin/bash
set -e
mkdir -p /logs/verifier

# Terminate any agent-owned helper processes before validation.
pkill -KILL -u user 2>/dev/null || true

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import subprocess
import pytest

ORACLE_PATH = "/app/oracle"
AGENT_SCRIPT = "/home/user/solution.sh"
N_ITERATIONS = 500


def generate_cases():
    rng = random.Random(42)
    cases = []
    for _ in range(N_ITERATIONS):
        length = rng.randint(1, 256)
        cases.append(bytes(rng.choices(range(256), k=length)))
    return cases


@pytest.fixture(scope="session")
def oracle_cases():
    """Compute trusted answers, then remove the oracle before executing the agent."""
    assert os.path.exists(ORACLE_PATH), f"Oracle binary missing at {ORACLE_PATH}"
    assert os.path.isfile(ORACLE_PATH), f"Oracle path {ORACLE_PATH} is not a file"

    results = []
    for i, input_data in enumerate(generate_cases()):
        try:
            proc = subprocess.run(
                [ORACLE_PATH],
                input=input_data,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=2,
            )
        except subprocess.TimeoutExpired:
            pytest.fail(f"Oracle timed out on iteration {i} with input length {len(input_data)}.")

        assert proc.returncode == 0, (
            f"Oracle failed on iteration {i}: "
            f"{proc.stderr.decode(errors='replace')}"
        )
        results.append((input_data, proc.stdout))

    # Delegating to the validation oracle must not be possible while the
    # submitted script is running.
    os.unlink(ORACLE_PATH)
    assert not os.path.exists(ORACLE_PATH)
    return results


def test_solution_exists(oracle_cases):
    """Ensure the agent created a standalone regular script."""
    assert os.path.exists(AGENT_SCRIPT), f"Solution script missing at {AGENT_SCRIPT}"
    assert os.path.isfile(AGENT_SCRIPT), f"Solution path {AGENT_SCRIPT} is not a file"
    assert not os.path.islink(AGENT_SCRIPT), f"Solution path {AGENT_SCRIPT} must not be a symlink"


def test_fuzz_equivalence(oracle_cases):
    """Fuzz the agent's script against answers produced by the oracle."""
    assert os.path.exists(AGENT_SCRIPT), f"Agent script missing at {AGENT_SCRIPT}"

    for i, (input_data, oracle_out) in enumerate(oracle_cases):
        try:
            agent_proc = subprocess.run(
                ["bash", AGENT_SCRIPT],
                input=input_data,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=5,
            )
        except subprocess.TimeoutExpired:
            pytest.fail(f"Agent script timed out on iteration {i} with input length {len(input_data)}.")

        if agent_proc.returncode != 0:
            pytest.fail(
                f"Agent script exited with status {agent_proc.returncode} on iteration {i}.\n"
                f"Agent stderr: {agent_proc.stderr.decode(errors='replace')}"
            )

        agent_out = agent_proc.stdout
        if oracle_out != agent_out:
            disp_input = input_data.hex()
            disp_oracle = oracle_out.hex()
            disp_agent = agent_out.hex()

            if len(disp_input) > 100:
                disp_input = disp_input[:100] + "..."
            if len(disp_oracle) > 100:
                disp_oracle = disp_oracle[:100] + "..."
            if len(disp_agent) > 100:
                disp_agent = disp_agent[:100] + "..."

            pytest.fail(
                f"Mismatch on iteration {i} with input length {len(input_data)}.\n"
                f"Input (hex): {disp_input}\n"
                f"Oracle output (hex): {disp_oracle}\n"
                f"Agent output (hex): {disp_agent}\n"
                f"Agent stderr: {agent_proc.stderr.decode(errors='replace')}"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
