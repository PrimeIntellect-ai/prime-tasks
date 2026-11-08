#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import string
import subprocess
import urllib.parse
import pytest

AGENT_PATH = "/home/user/config_tracker"
NUM_FUZZ_TESTS = 1000
TRACKED_KEYS = {"host", "port", "timeout", "retries"}
PREFIX = "TRK-v9"


def generate_fuzz_input(seed):
    random.seed(seed)
    lines = []
    num_lines = random.randint(5, 100)
    target_keys = ['host', 'port', 'timeout', 'retries']

    for _ in range(num_lines):
        if random.random() < 0.6:
            key = random.choice(target_keys)
            key = "".join(random.choice([c.lower(), c.upper()]) for c in key)
        else:
            key = "".join(random.choices(string.ascii_letters + string.digits, k=random.randint(3, 10)))

        space1 = " " * random.randint(0, 3) + "\t" * random.randint(0, 2)
        space2 = " " * random.randint(0, 3) + "\t" * random.randint(0, 2)
        space3 = " " * random.randint(0, 3) + "\t" * random.randint(0, 2)
        space4 = " " * random.randint(0, 3) + "\t" * random.randint(0, 2)

        if key.lower() == 'retries' and random.random() < 0.8:
            val = str(random.randint(-50, 50))
        else:
            raw_val = "".join(random.choices(string.ascii_letters + string.digits + " -_.:/", k=random.randint(1, 30)))
            val = urllib.parse.quote(raw_val)

        if random.random() < 0.3:
            val = urllib.parse.quote(val)

        lines.append(f"{space1}{key}{space2}:{space3}{val}{space4}")

    return "\n".join(lines).encode('utf-8')


def expected_output(input_data):
    state = {}
    text = input_data.decode('utf-8', errors='replace')

    for line in text.splitlines():
        if ':' not in line:
            continue
        key, value = line.split(':', 1)
        key = key.strip().lower()
        value = value.strip()
        if key not in TRACKED_KEYS:
            continue

        decoded = urllib.parse.unquote(value)
        if key == 'retries' and re.fullmatch(r'[+-]?[0-9]+', decoded):
            if int(decoded) < 0:
                decoded = '0'
        state[key] = decoded

    return ''.join(
        f"{PREFIX}-{key}={state[key]}\n" for key in sorted(state)
    ).encode('utf-8')


def run_agent(input_data):
    proc = subprocess.run(
        [AGENT_PATH], input=input_data, capture_output=True, timeout=5
    )
    assert proc.returncode == 0, (
        f"Agent exited with status {proc.returncode}.\n"
        f"STDERR:\n{proc.stderr.decode('utf-8', errors='replace')}"
    )
    return proc.stdout


def test_executable_exists():
    assert os.path.isfile(AGENT_PATH), f"Agent executable not found at {AGENT_PATH}"
    assert os.access(AGENT_PATH, os.X_OK), f"Agent executable {AGENT_PATH} is not executable"


def test_validation_cases():
    cases = [
        b"retries: banana\n",
        b"retries: -12\n",
        b"retries: %2D7\n",
        b"retries: 8\nretries: not-a-number\n",
        b"TIMEOUT: a%3Ab\nHOST: example%20host\nPORT: 8080\n",
    ]
    for input_data in cases:
        assert run_agent(input_data) == expected_output(input_data)


def test_fuzz_equivalence():
    for i in range(NUM_FUZZ_TESTS):
        input_data = generate_fuzz_input(i)
        expected = expected_output(input_data)
        actual = run_agent(input_data)
        if actual != expected:
            pytest.fail(
                f"Mismatch on fuzz iteration {i}.\n\n"
                f"INPUT:\n{input_data.decode('utf-8', errors='replace')}\n\n"
                f"EXPECTED OUTPUT:\n{expected.decode('utf-8', errors='replace')}\n\n"
                f"ACTUAL OUTPUT:\n{actual.decode('utf-8', errors='replace')}\n"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
