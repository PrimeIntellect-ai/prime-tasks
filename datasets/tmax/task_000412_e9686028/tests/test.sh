#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import random
import subprocess
import pytest

ORACLE_PATH = "/app/oracle"
AGENT_SCRIPT = "/home/user/aggregator.py"

def generate_fuzz_input(num_lines):
    locales = ["es-ES", "fr-FR", "de-DE", "ja-JP", "pt-BR"]
    events = ["translated", "reviewed", "failed", "queued", "retry"]

    lines = []
    prev_line = None
    for _ in range(num_lines):
        if prev_line and random.random() < 0.2:
            lines.append(prev_line)
            continue

        ts = random.randint(1680000000, 1681000000)
        locale = random.choice(locales)
        event = random.choice(events)
        wc = random.randint(1, 250)

        line = f"{ts},{locale},{event},{wc}"
        lines.append(line)
        prev_line = line

    return "\n".join(lines) + "\n"

def run_process(cmd, input_data):
    result = subprocess.run(
        cmd,
        input=input_data,
        text=True,
        capture_output=True,
        check=False
    )
    return result.returncode, result.stdout, result.stderr

def test_aggregator_fuzz_equivalence():
    assert os.path.exists(ORACLE_PATH), f"Oracle binary missing at {ORACLE_PATH}"
    assert os.path.exists(AGENT_SCRIPT), f"Agent script missing at {AGENT_SCRIPT}"

    random.seed(42)

    for i in range(200):
        num_lines = random.randint(10, 5000)
        input_data = generate_fuzz_input(num_lines)

        oracle_code, oracle_out, oracle_err = run_process([ORACLE_PATH], input_data)
        agent_code, agent_out, agent_err = run_process(["python3", AGENT_SCRIPT], input_data)

        assert agent_code == 0, f"Agent script failed on iteration {i} with error:\n{agent_err}"
        assert oracle_code == 0, f"Oracle failed on iteration {i} with error:\n{oracle_err}"

        assert agent_out == oracle_out, (
            f"Output mismatch on iteration {i} with {num_lines} lines.\n"
            f"--- Input (first 10 lines) ---\n"
            f"{chr(10).join(input_data.splitlines()[:10])}\n"
            f"--- Oracle Output ---\n{oracle_out}\n"
            f"--- Agent Output ---\n{agent_out}\n"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
