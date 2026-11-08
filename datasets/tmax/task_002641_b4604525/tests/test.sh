#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import random
import subprocess
import pytest

def generate_fuzz_inputs(n=10000, seed=42):
    random.seed(seed)
    inputs = []
    schemes = [b"http://", b"https://", b"ftp://", b"", b"ht tp://", b"://"]
    domains = [b"example.com", b"test.org", b"localhost", b"127.0.0.1", b""]
    paths = [b"/a/b/c", b"/", b"/index.html", b"", b"/%20/foo\xffbar"]

    for _ in range(n):
        length = random.randint(10, 2000)
        scheme = random.choice(schemes)
        domain = random.choice(domains)
        path = random.choice(paths)
        base = scheme + domain + path

        rem_length = max(0, length - len(base))
        noise = bytearray(random.getrandbits(8) for _ in range(rem_length))

        # Remove newlines and carriage returns to ensure one URL per line
        for i in range(len(noise)):
            if noise[i] in (10, 13):
                noise[i] = 32

        url_bytes = base + noise
        inputs.append(url_bytes)

    return b"\n".join(inputs) + b"\n"

def test_fuzz_equivalence():
    oracle_path = "/tests/legacy_url_parser_bin"
    agent_script = "/home/user/run_parser.py"

    assert os.path.exists(oracle_path), f"Oracle binary not found at {oracle_path}"
    assert os.path.exists(agent_script), f"Agent script not found at {agent_script}"

    # Generate 10,000 fuzzing inputs
    fuzz_data = generate_fuzz_inputs(n=10000, seed=1337)

    # Run Oracle
    oracle_proc = subprocess.run(
        [oracle_path],
        input=fuzz_data,
        capture_output=True,
        check=False
    )

    # Run Agent
    agent_proc = subprocess.run(
        ["python3", agent_script],
        input=fuzz_data,
        capture_output=True,
        check=False
    )

    # Check if agent script crashed
    if agent_proc.returncode != 0 and oracle_proc.returncode == 0:
        pytest.fail(f"Agent script failed with return code {agent_proc.returncode}\nStderr: {agent_proc.stderr.decode('utf-8', errors='replace')}")

    oracle_lines = oracle_proc.stdout.split(b"\n")
    agent_lines = agent_proc.stdout.split(b"\n")
    input_lines = fuzz_data.split(b"\n")

    assert len(oracle_lines) == len(agent_lines), "Agent output line count does not match oracle."

    for i, (o_line, a_line) in enumerate(zip(oracle_lines, agent_lines)):
        if o_line != a_line:
            inp = input_lines[i].decode('utf-8', errors='replace')
            o_str = o_line.decode('utf-8', errors='replace')
            a_str = a_line.decode('utf-8', errors='replace')
            pytest.fail(
                f"Mismatch at line {i+1}:\n"
                f"Input: {inp}\n"
                f"Oracle Output: {o_str}\n"
                f"Agent Output:  {a_str}"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
