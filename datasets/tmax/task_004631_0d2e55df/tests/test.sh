#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import random
import subprocess
import pytest

def generate_fuzz_input(seed):
    random.seed(seed)
    num_lines = random.randint(500, 5000)
    lines = []
    ts = 1600000000
    devices = ["DEV_A", "DEV_B", "DEV_C", "DEV_D", "DEV_X"]
    last_row = None

    for _ in range(num_lines):
        ts += random.randint(1, 10)
        dev = random.choice(devices)

        # 10% chance to duplicate the last row exactly to test deduplication
        if last_row and random.random() < 0.10:
            lines.append(last_row)
            continue

        # 5% chance to inject a bad reading to test cleaning
        if random.random() < 0.05:
            reading = random.choice(["err", "NaN", "bad", ""])
        else:
            reading = str(random.randint(0, 40))

        row = f"{ts},{dev},{reading}"
        lines.append(row)
        last_row = row

    return "\n".join(lines) + "\n"

def test_agent_script_exists_and_executable():
    agent_script = "/home/user/process.py"
    assert os.path.exists(agent_script), f"Agent script {agent_script} does not exist."
    assert os.access(agent_script, os.X_OK), f"Agent script {agent_script} is not executable."

def test_fuzz_equivalence():
    agent_script = "/home/user/process.py"
    oracle_bin = "/tests/oracle_bin"

    assert os.path.exists(oracle_bin), f"Oracle binary {oracle_bin} missing."

    for i in range(50):
        input_data = generate_fuzz_input(i)

        proc_oracle = subprocess.run(
            [oracle_bin],
            input=input_data,
            text=True,
            capture_output=True
        )
        assert proc_oracle.returncode == 0, f"Oracle failed on run {i}:\n{proc_oracle.stderr}"

        proc_agent = subprocess.run(
            [agent_script],
            input=input_data,
            text=True,
            capture_output=True
        )
        assert proc_agent.returncode == 0, f"Agent script failed on run {i}:\n{proc_agent.stderr}"

        if proc_oracle.stdout != proc_agent.stdout:
            # Truncate output for readable error message if it's too long
            oracle_out = proc_oracle.stdout
            agent_out = proc_agent.stdout

            if len(oracle_out) > 1000:
                oracle_out = oracle_out[:1000] + "\n...[truncated]"
            if len(agent_out) > 1000:
                agent_out = agent_out[:1000] + "\n...[truncated]"

            pytest.fail(
                f"Output mismatch on fuzz run {i}!\n\n"
                f"--- Oracle Output ---\n{oracle_out}\n\n"
                f"--- Agent Output ---\n{agent_out}\n"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
