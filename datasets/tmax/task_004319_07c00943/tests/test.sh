#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import json
import random
import string
import subprocess
import sys
import os
import pytest

def generate_random_email():
    local = ''.join(random.choices(string.ascii_lowercase, k=random.randint(3, 8)))
    domain = ''.join(random.choices(string.ascii_lowercase, k=random.randint(3, 8)))
    return f"{local}@{domain}.com"

def generate_random_date_str():
    year = random.randint(2000, 2023)
    month = random.randint(1, 12)
    day = random.randint(1, 28)
    formats = [
        f"{year}-{month:02d}-{day:02d}",
        f"{month}/{day}/{year}",
        f"{year}/{month:02d}/{day:02d} {random.randint(0,23):02d}:{random.randint(0,59):02d}:{random.randint(0,59):02d}",
        f"{day}-{month}-{year}"
    ]
    return random.choice(formats)

def generate_input():
    num_objects = random.randint(10, 100)
    data = []
    for _ in range(num_objects):
        amt = None if random.random() < 0.3 else round(random.uniform(10.0, 1000.0), 2)
        data.append({
            "id": random.randint(1, 50),
            "email": generate_random_email(),
            "amount": amt,
            "date_str": generate_random_date_str()
        })
    return data

def test_vendored_package_fixed():
    path = "/app/vendor/python-dateutil/dateutil/parser/_parser.py"
    assert os.path.exists(path), f"File {path} is missing."
    with open(path, 'r') as f:
        content = f.read()
    assert "import warnngs" not in content, f"Typo 'import warnngs' still exists in {path}."
    assert "import warnings" in content, f"Expected 'import warnings' not found in {path}."

def test_dateutil_installed():
    try:
        from dateutil import parser
        res = parser.parse("2023-01-01")
        assert res.year == 2023, "Parsed year is incorrect, dateutil might not be functioning properly."
    except Exception as e:
        pytest.fail(f"dateutil parsing failed, package might not be installed correctly: {e}")

def test_fuzz_equivalence():
    agent_script = "/home/user/process_etl.py"
    oracle_script = "/tests/oracle_process_etl.py"

    assert os.path.exists(agent_script), f"Agent script {agent_script} not found."
    assert os.path.exists(oracle_script), f"Oracle script {oracle_script} not found."

    random.seed(42)

    for i in range(200):
        input_data = generate_input()
        input_json = json.dumps(input_data)

        oracle_proc = subprocess.run(
            [sys.executable, oracle_script],
            input=input_json,
            text=True,
            capture_output=True
        )
        assert oracle_proc.returncode == 0, f"Oracle failed on iteration {i}: {oracle_proc.stderr}"

        agent_proc = subprocess.run(
            [sys.executable, agent_script],
            input=input_json,
            text=True,
            capture_output=True
        )
        assert agent_proc.returncode == 0, f"Agent script failed on iteration {i}: {agent_proc.stderr}"

        oracle_out = oracle_proc.stdout.strip()
        agent_out = agent_proc.stdout.strip()

        assert oracle_out == agent_out, \
            f"Mismatch on iteration {i}.\nInput: {input_json}\nOracle Output: {oracle_out}\nAgent Output: {agent_out}"

def test_fuzz_equivalence_empty():
    agent_script = "/home/user/process_etl.py"
    oracle_script = "/tests/oracle_process_etl.py"

    input_json = "[]"
    oracle_proc = subprocess.run(
        [sys.executable, oracle_script],
        input=input_json,
        text=True,
        capture_output=True
    )
    agent_proc = subprocess.run(
        [sys.executable, agent_script],
        input=input_json,
        text=True,
        capture_output=True
    )
    assert oracle_proc.stdout.strip() == agent_proc.stdout.strip(), "Mismatch on empty array input."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
