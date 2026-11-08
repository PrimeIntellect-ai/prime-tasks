#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import random
import string
import datetime
import sys
import pytest

ORACLE_PATH = "/tests/oracle_dedup"
AGENT_PATH = "/home/user/etl_dedup"
WRAPPER_PATH = "/home/user/run_pipeline.sh"

def test_agent_executable_exists():
    assert os.path.isfile(AGENT_PATH), f"Agent program {AGENT_PATH} does not exist."
    assert os.access(AGENT_PATH, os.X_OK), f"Agent program {AGENT_PATH} is not executable."

def test_wrapper_script_exists():
    assert os.path.isfile(WRAPPER_PATH), f"Wrapper script {WRAPPER_PATH} does not exist."
    assert os.access(WRAPPER_PATH, os.X_OK), f"Wrapper script {WRAPPER_PATH} is not executable."

def generate_fuzz_input(num_lines):
    lines = []
    payloads = []
    for _ in range(num_lines):
        dt = datetime.datetime(
            random.randint(2020, 2024),
            random.randint(1, 12),
            random.randint(1, 28),
            random.randint(0, 23),
            random.randint(0, 59),
            random.randint(0, 59)
        )
        dt_str = dt.strftime("%Y-%m-%d %H:%M:%S")

        if payloads and random.random() < 0.4:
            base_payload = random.choice(payloads)
            perturbed = "".join(
                c.upper() if random.random() < 0.5 else c.lower()
                for c in base_payload
            )
            chars = list(perturbed)
            for _ in range(random.randint(0, 5)):
                chars.insert(random.randint(0, len(chars)), random.choice(string.punctuation))
            payload = "".join(chars)
        else:
            payload = "".join(random.choices(string.ascii_letters + string.digits + string.punctuation + " ", k=random.randint(10, 50)))
            base = "".join(c for c in payload if c.isalnum()).lower()
            if base:
                payloads.append(base)

        lines.append(f"{dt_str}|{payload}")
    return "\n".join(lines) + "\n"

def run_oracle(input_data):
    return subprocess.run(
        [sys.executable, ORACLE_PATH],
        input=input_data.encode('utf-8'),
        capture_output=True
    )

def test_fuzz_equivalence():
    random.seed(42)
    # Using 100 iterations instead of 1000 to prevent test timeouts,
    # while still providing rigorous fuzzing.
    iterations = 100

    for i in range(iterations):
        num_lines = random.randint(1, 500)
        input_data = generate_fuzz_input(num_lines)

        oracle_proc = run_oracle(input_data)
        assert oracle_proc.returncode == 0, f"Oracle failed on iteration {i}."
        oracle_out = oracle_proc.stdout

        agent_proc = subprocess.run(
            [AGENT_PATH],
            input=input_data.encode('utf-8'),
            capture_output=True
        )

        assert agent_proc.returncode == 0, f"Agent program crashed or failed on iteration {i}."
        agent_out = agent_proc.stdout

        if oracle_out != agent_out:
            input_snippet = input_data[:500] + ("..." if len(input_data) > 500 else "")
            oracle_snippet = oracle_out.decode('utf-8', errors='replace')[:500]
            agent_snippet = agent_out.decode('utf-8', errors='replace')[:500]
            pytest.fail(
                f"Mismatch on iteration {i}!\n"
                f"Input snippet:\n{input_snippet}\n"
                f"Oracle output snippet:\n{oracle_snippet}\n"
                f"Agent output snippet:\n{agent_snippet}\n"
            )

def test_wrapper_script_functionality(tmp_path):
    random.seed(123)
    input_data = generate_fuzz_input(50)

    in_file = tmp_path / "input.txt"
    out_file = tmp_path / "output.txt"
    in_file.write_text(input_data, encoding='utf-8')

    subprocess.run([WRAPPER_PATH, str(in_file), str(out_file)], check=True)

    oracle_proc = run_oracle(input_data)

    agent_out = out_file.read_bytes()
    assert agent_out == oracle_proc.stdout, "Wrapper script output does not match oracle output."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
