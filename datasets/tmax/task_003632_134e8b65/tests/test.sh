#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import string
import subprocess
import tempfile
from pathlib import Path

def generate_random_string(min_len, max_len):
    length = random.randint(min_len, max_len)
    return ''.join(random.choices(string.ascii_letters + string.digits + " !@#$%^&*()", k=length)).replace('"', "'").replace('\\', '')

def generate_fuzz_input(n_lines: int) -> str:
    lines = []
    for _ in range(n_lines):
        choice = random.choices(
            [0, 1, 2, 3, 4],
            weights=[0.3, 0.2, 0.3, 0.2, 0.1],
            k=1
        )[0]

        if choice == 0:
            msg = generate_random_string(10, 50)
            ts = random.randint(10000, 99999)
            line = f'{{"message": "{msg}", "timestamp": {ts}}}'
        elif choice == 1:
            err = generate_random_string(5, 20)
            line = f'{{"error": "{err}"}}'
        elif choice == 2:
            c1 = random.choice(['G', 'M'])
            d1 = random.randint(0, 200)
            c2 = random.choice(['X', 'Y', 'Z'])
            d2 = random.randint(0, 100)
            c3 = random.choice(['E', 'F'])
            d3 = random.randint(0, 500)
            line = f'{c1}{d1} {c2}{d2} {c3}{d3}'
        elif choice == 3:
            txt = generate_random_string(5, 30)
            line = f'random text {txt}'
        elif choice == 4:
            txt = generate_random_string(5, 20)
            line = f'M117 {txt}'

        lines.append(line)
    return "\n".join(lines) + "\n"

def test_fuzz_equivalence():
    """Test that the agent's parser behaves exactly like the oracle on random inputs."""
    agent_script = Path("/home/user/parser.sh")
    oracle_script = Path("/tests/reference_parser")

    assert agent_script.exists(), f"Agent script not found at {agent_script}"
    assert os.access(agent_script, os.X_OK), f"Agent script {agent_script} is not executable"

    assert oracle_script.exists(), f"Oracle script not found at {oracle_script}"
    assert os.access(oracle_script, os.X_OK), f"Oracle script {oracle_script} is not executable"

    random.seed(42)

    # Generate random test file
    fuzz_content = generate_fuzz_input(500)

    with tempfile.NamedTemporaryFile(mode="w", delete=False) as f:
        f.write(fuzz_content)
        temp_path = f.name

    try:
        # Run oracle
        oracle_res = subprocess.run(
            [str(oracle_script), temp_path],
            capture_output=True,
            text=True
        )
        assert oracle_res.returncode == 0, f"Oracle failed with error: {oracle_res.stderr}"

        # Run agent
        agent_res = subprocess.run(
            [str(agent_script), temp_path],
            capture_output=True,
            text=True
        )

        # Compare outputs
        oracle_lines = oracle_res.stdout.splitlines()
        agent_lines = agent_res.stdout.splitlines()

        if oracle_lines != agent_lines:
            # Find the first differing line
            for i, (o_line, a_line) in enumerate(zip(oracle_lines, agent_lines)):
                if o_line != a_line:
                    assert False, (
                        f"Output mismatch at output line {i+1}:\n"
                        f"Expected (Oracle): {o_line}\n"
                        f"Got (Agent)      : {a_line}\n"
                    )

            # If lengths differ
            assert len(oracle_lines) == len(agent_lines), (
                f"Output length mismatch. Oracle produced {len(oracle_lines)} lines, "
                f"Agent produced {len(agent_lines)} lines."
            )

    finally:
        os.remove(temp_path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
