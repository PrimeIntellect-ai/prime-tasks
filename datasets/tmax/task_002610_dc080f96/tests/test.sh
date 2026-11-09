#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import random
import subprocess
import tempfile
import pytest
from datetime import datetime, timedelta, timezone

def generate_fuzz_input(seed: int) -> bytes:
    random.seed(seed)
    num_lines = random.randint(0, 50000)
    lines = []
    base_time = datetime(2023, 5, 10, tzinfo=timezone.utc)

    for _ in range(num_lines):
        is_valid = random.random() < 0.7
        dt = base_time + timedelta(seconds=random.randint(0, 48 * 3600))
        ts_str = dt.strftime("%Y-%m-%dT%H:%M:%SZ")
        ev_type = random.choice(["sale", "refund"])
        amount = round(random.uniform(1.0, 1000.0), 2)

        if is_valid:
            lines.append(json.dumps({"timestamp": ts_str, "type": ev_type, "amount": amount}))
        else:
            # Generate invalid JSON with a broken unicode escape
            bad_str = f'{{"timestamp": "{ts_str}", "type": "{ev_type}", "amount": {amount}, "notes": "\\u12ZZ"}}'
            lines.append(bad_str)

    # Join with newlines and add a trailing newline
    content = "\n".join(lines)
    if content:
        content += "\n"
    return content.encode('utf-8')

@pytest.fixture(scope="session")
def compiled_agent_binary():
    agent_src = "/home/user/processor.go"
    assert os.path.isfile(agent_src), f"Agent source code is missing at {agent_src}"

    bin_path = "/tmp/agent_processor"
    res = subprocess.run(["go", "build", "-o", bin_path, agent_src], capture_output=True, text=True)
    assert res.returncode == 0, f"Agent code failed to compile:\n{res.stderr}"
    return bin_path

def test_fuzz_equivalence(compiled_agent_binary):
    oracle_bin = "/tests/oracle_processor"
    assert os.path.isfile(oracle_bin), f"Oracle binary missing at {oracle_bin}"
    assert os.access(oracle_bin, os.X_OK), f"Oracle binary is not executable at {oracle_bin}"

    # Run N=100 iterations
    N = 100
    for i in range(N):
        input_data = generate_fuzz_input(seed=42 + i)

        # Run oracle
        oracle_proc = subprocess.run(
            [oracle_bin],
            input=input_data,
            capture_output=True,
            timeout=10
        )
        assert oracle_proc.returncode == 0, f"Oracle failed on iteration {i}:\n{oracle_proc.stderr.decode('utf-8', errors='replace')}"
        oracle_out = oracle_proc.stdout

        # Run agent
        agent_proc = subprocess.run(
            [compiled_agent_binary],
            input=input_data,
            capture_output=True,
            timeout=10
        )
        assert agent_proc.returncode == 0, f"Agent program failed on iteration {i}:\n{agent_proc.stderr.decode('utf-8', errors='replace')}"
        agent_out = agent_proc.stdout

        if oracle_out != agent_out:
            # Provide a helpful error message with a sample of the mismatch
            oracle_str = oracle_out.decode('utf-8', errors='replace')
            agent_str = agent_out.decode('utf-8', errors='replace')
            pytest.fail(
                f"Mismatch on iteration {i} (seed {42+i}).\n"
                f"Input lines: {len(input_data.splitlines())}\n"
                f"--- Oracle Output (first 500 chars) ---\n{oracle_str[:500]}\n"
                f"--- Agent Output (first 500 chars) ---\n{agent_str[:500]}\n"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
