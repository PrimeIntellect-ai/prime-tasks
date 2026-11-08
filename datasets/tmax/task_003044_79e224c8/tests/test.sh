#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import base64
import subprocess
import pytest

def generate_fuzz_input(seed, num_lines=1000):
    rng = random.Random(seed)
    lines = []
    keys = ['A', 'B', 'C']
    values = ['v1', 'v2', '']
    encodings = ['b64', 'hex', 'utf']

    for _ in range(num_lines):
        ts = rng.randint(1600000000, 1600010000)
        enc = rng.choice(encodings)

        if rng.random() < 0.1:
            raw_str = f"MALFORMED_STRING_{rng.randint(1, 100)}"
        else:
            k = rng.choice(keys)
            v = rng.choice(values)
            raw_str = f"{k}={v}"

        raw_bytes = raw_str.encode('utf-8')

        if enc == 'b64':
            payload = base64.b64encode(raw_bytes).decode('utf-8')
        elif enc == 'hex':
            payload = raw_bytes.hex()
        else:
            payload = "some_invalid_payload"

        if rng.random() < 0.05:
            lines.append(f"INVALID LINE FORMAT {ts} {enc} {payload}")
        else:
            lines.append(f"[{ts}] {{{enc}}} - {payload}")

    return "\n".join(lines) + "\n"

def test_fuzz_equivalence():
    agent_script = "/home/user/parse_log.py"
    oracle_script = "/tests/oracle.py"

    assert os.path.exists(agent_script), f"Agent script {agent_script} not found."
    assert os.path.exists(oracle_script), f"Oracle script {oracle_script} not found."

    for seed in range(5):
        input_data = generate_fuzz_input(seed, 1000)

        agent_proc = subprocess.run(
            ["python3", agent_script],
            input=input_data,
            text=True,
            capture_output=True
        )

        oracle_proc = subprocess.run(
            ["python3", oracle_script],
            input=input_data,
            text=True,
            capture_output=True
        )

        assert agent_proc.returncode == 0, f"Agent script failed with error:\n{agent_proc.stderr}"
        assert oracle_proc.returncode == 0, f"Oracle script failed with error:\n{oracle_proc.stderr}"

        if agent_proc.stdout != oracle_proc.stdout:
            expected = oracle_proc.stdout[:1000]
            actual = agent_proc.stdout[:1000]
            pytest.fail(
                f"Outputs differ on seed {seed}.\n\n"
                f"Expected (Oracle) snippet:\n{expected}\n\n"
                f"Actual (Agent) snippet:\n{actual}\n"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
