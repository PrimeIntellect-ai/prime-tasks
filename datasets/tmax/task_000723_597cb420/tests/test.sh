#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import string
import subprocess
import pytest

AGENT_SCRIPT = "/home/user/path_validator.py"
ORACLE_SCRIPT = "/tests/oracle_validator.py"
N_ITERATIONS = 1000

def generate_base_dir():
    segments = [""] + [
        "".join(random.choices(string.ascii_lowercase + string.digits, k=random.randint(3, 8)))
        for _ in range(random.randint(2, 5))
    ]
    return "/".join(segments)

def generate_untrusted_path():
    choices = ["..", ".", ""] + [
        "".join(random.choices(string.ascii_lowercase + string.digits, k=random.randint(3, 8)))
        for _ in range(5)
    ]
    segments = [random.choice(choices) for _ in range(random.randint(1, 20))]
    path = "/".join(segments)
    # Occasionally make it an absolute path
    if random.random() < 0.2:
        path = "/" + path.lstrip("/")
    return path

def test_agent_script_exists():
    assert os.path.exists(AGENT_SCRIPT), f"Agent script missing at {AGENT_SCRIPT}"
    assert os.path.isfile(AGENT_SCRIPT), f"{AGENT_SCRIPT} is not a file"

def test_oracle_script_exists():
    assert os.path.exists(ORACLE_SCRIPT), f"Oracle script missing at {ORACLE_SCRIPT}"

def test_fuzz_equivalence():
    assert os.path.exists(AGENT_SCRIPT), f"Agent script missing at {AGENT_SCRIPT}"
    assert os.path.exists(ORACLE_SCRIPT), f"Oracle script missing at {ORACLE_SCRIPT}"

    random.seed(42)

    for i in range(N_ITERATIONS):
        base_dir = generate_base_dir()
        untrusted_path = generate_untrusted_path()

        # Run oracle
        oracle_cmd = ["python3", ORACLE_SCRIPT, base_dir, untrusted_path]
        try:
            oracle_res = subprocess.run(oracle_cmd, capture_output=True, text=True, timeout=0.5, check=True)
            oracle_output = oracle_res.stdout.strip()
        except subprocess.TimeoutExpired:
            pytest.fail(f"Oracle timed out on input: base_dir='{base_dir}', untrusted_path='{untrusted_path}'")
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Oracle failed on input: base_dir='{base_dir}', untrusted_path='{untrusted_path}'. Error: {e.stderr}")

        # Run agent
        agent_cmd = ["python3", AGENT_SCRIPT, base_dir, untrusted_path]
        try:
            agent_res = subprocess.run(agent_cmd, capture_output=True, text=True, timeout=0.5)
            agent_output = agent_res.stdout.strip()
        except subprocess.TimeoutExpired:
            pytest.fail(f"Agent timed out on input: base_dir='{base_dir}', untrusted_path='{untrusted_path}'")

        assert agent_output == oracle_output, (
            f"Output mismatch on iteration {i+1}.\n"
            f"Base dir: {repr(base_dir)}\n"
            f"Untrusted path: {repr(untrusted_path)}\n"
            f"Expected (Oracle): {repr(oracle_output)}\n"
            f"Got (Agent): {repr(agent_output)}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
