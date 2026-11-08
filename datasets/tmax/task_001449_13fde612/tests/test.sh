#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import sys
import subprocess
import random
import string
import pytest

ORACLE_PATH = "/app/legacy_audit_processor"
AGENT_SCRIPT = "/home/user/audit_processor.py"
NUM_TESTS = 200

def generate_random_string(length):
    return ''.join(random.choices(string.ascii_letters + string.digits, k=length))

def generate_ssn():
    return f"{random.randint(100, 999)}-{random.randint(10, 99)}-{random.randint(1000, 9999)}"

def generate_cwe22():
    return random.choice(["../", "..\\"])

def generate_test_cases(n=NUM_TESTS, seed=42):
    random.seed(seed)
    cases = []

    for _ in range(n):
        length = random.randint(20, 150)
        base_str = generate_random_string(length)

        prob = random.random()

        if prob < 0.3:
            # SSN only
            insert_pos = random.randint(0, len(base_str))
            case = base_str[:insert_pos] + generate_ssn() + base_str[insert_pos:]
        elif prob < 0.6:
            # CWE-22 only
            insert_pos = random.randint(0, len(base_str))
            case = base_str[:insert_pos] + generate_cwe22() + base_str[insert_pos:]
        elif prob < 0.8:
            # Both
            insert_pos1 = random.randint(0, len(base_str))
            case = base_str[:insert_pos1] + generate_ssn() + base_str[insert_pos1:]
            insert_pos2 = random.randint(0, len(case))
            case = case[:insert_pos2] + generate_cwe22() + case[insert_pos2:]
        else:
            # None (purely random printable ASCII)
            case = ''.join(random.choices(string.printable, k=length))

        # Occasionally add trailing newlines to test rstrip behavior
        if random.random() < 0.5:
            case += "\n"

        cases.append(case)

    return cases

def run_program(cmd, input_data):
    result = subprocess.run(
        cmd,
        input=input_data.encode('utf-8'),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=2
    )
    return result.stdout

def test_agent_script_exists():
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script missing at {AGENT_SCRIPT}"

def test_fuzz_equivalence():
    assert os.path.isfile(ORACLE_PATH), f"Oracle missing at {ORACLE_PATH}"
    assert os.access(ORACLE_PATH, os.X_OK), f"Oracle at {ORACLE_PATH} is not executable"

    test_cases = generate_test_cases()

    for i, case in enumerate(test_cases):
        oracle_out = run_program([ORACLE_PATH], case)

        try:
            agent_out = run_program([sys.executable, AGENT_SCRIPT], case)
        except subprocess.TimeoutExpired:
            pytest.fail(f"Agent script timed out on input {i}:\n{repr(case)}")
        except Exception as e:
            pytest.fail(f"Agent script failed on input {i}:\n{repr(case)}\nError: {e}")

        assert agent_out == oracle_out, (
            f"Output mismatch on input {i}:\n"
            f"Input: {repr(case)}\n"
            f"Oracle output: {repr(oracle_out)}\n"
            f"Agent output:  {repr(agent_out)}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
