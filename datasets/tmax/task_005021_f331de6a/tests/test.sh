#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import uuid
import random
import subprocess
import tempfile
import pytest

ORACLE_PATH = "/app/legacy_cleaner"
AGENT_PATH = "/home/user/cleaner.py"

def generate_random_unicode(length=15):
    ranges = [
        (0x0041, 0x005A),  # A-Z
        (0x0061, 0x007A),  # a-z
        (0x0600, 0x06FF),  # Arabic
        (0x4E00, 0x9FFF),  # CJK
        (0x1F300, 0x1F5FF) # Emojis
    ]
    res = []
    for _ in range(length):
        r = random.choice(ranges)
        res.append(chr(random.randint(r[0], r[1])))
    s = "".join(res)
    if random.random() < 0.3:
        nl = random.choice(["\n", "\r\n"])
        insert_pos = random.randint(1, length - 1)
        s = s[:insert_pos] + nl + s[insert_pos:]
    return s

def generate_csv(filepath, num_rows):
    timestamps = sorted([random.randint(1600000000000, 1600003600000) for _ in range(num_rows)])

    messages_pool = []

    with open(filepath, 'w', newline='', encoding='utf-8') as f:
        writer = csv.writer(f)
        writer.writerow(["timestamp_ms", "user_id", "message"])
        for i in range(num_rows):
            ts = timestamps[i]
            if random.random() < 0.2:
                ts = ""

            uid = str(uuid.uuid4())

            if messages_pool and random.random() < 0.2:
                msg = random.choice(messages_pool)
            else:
                msg = generate_random_unicode(random.randint(5, 20))
                messages_pool.append(msg)

            writer.writerow([ts, uid, msg])

def test_agent_exists():
    assert os.path.exists(AGENT_PATH), f"Agent script {AGENT_PATH} not found."

def test_fuzz_equivalence():
    random.seed(42)
    num_tests = 100

    assert os.path.exists(ORACLE_PATH), f"Oracle {ORACLE_PATH} not found."
    assert os.path.exists(AGENT_PATH), f"Agent script {AGENT_PATH} not found."

    with tempfile.TemporaryDirectory() as tmpdir:
        for i in range(num_tests):
            num_rows = random.randint(10, 500)
            input_csv = os.path.join(tmpdir, f"input_{i}.csv")
            oracle_out = os.path.join(tmpdir, f"oracle_out_{i}.csv")
            agent_out = os.path.join(tmpdir, f"agent_out_{i}.csv")

            generate_csv(input_csv, num_rows)

            # Run oracle
            oracle_res = subprocess.run([ORACLE_PATH, input_csv, oracle_out], capture_output=True, text=True)
            assert oracle_res.returncode == 0, f"Oracle failed on test {i}:\n{oracle_res.stderr}"

            # Run agent
            agent_res = subprocess.run(["python3", AGENT_PATH, input_csv, agent_out], capture_output=True, text=True)
            assert agent_res.returncode == 0, f"Agent failed on test {i}:\n{agent_res.stderr}"

            # Compare
            with open(oracle_out, 'r', encoding='utf-8') as f:
                oracle_data = f.read()
            with open(agent_out, 'r', encoding='utf-8') as f:
                agent_data = f.read()

            if oracle_data != agent_data:
                pytest.fail(
                    f"Mismatch on test {i} ({num_rows} rows).\n"
                    f"Input file: {input_csv}\n"
                    f"--- Oracle Output ---\n{oracle_data[:500]}...\n"
                    f"--- Agent Output ---\n{agent_data[:500]}...\n"
                )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
