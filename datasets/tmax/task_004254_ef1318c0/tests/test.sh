#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import json
import uuid
import random
import string
import subprocess
import tempfile
import pytest

ORACLE_PATH = "/tests/oracle.py"
AGENT_SCRIPT = "/home/user/analyze.py"
VIDEO_PATH = "/app/surveillance.mp4"
NUM_ITERATIONS = 20

def generate_random_username():
    valid = random.choice([True, False])
    if valid:
        length = random.choice([3, 4])
        return ''.join(random.choices(string.ascii_uppercase, k=length))
    else:
        # Invalid usernames
        case = random.choice([1, 2, 3])
        if case == 1:
            return ''.join(random.choices(string.ascii_lowercase, k=3))
        elif case == 2:
            return ''.join(random.choices(string.ascii_uppercase, k=2))
        else:
            return ''.join(random.choices(string.ascii_uppercase + string.digits, k=4))

def generate_fuzz_data(seed):
    random.seed(seed)

    num_users = random.randint(10, 50)
    users_data = []
    event_ids = []
    for _ in range(num_users):
        eid = str(uuid.uuid4())
        event_ids.append(eid)
        uname = generate_random_username()
        users_data.append({"event_id": eid, "username": uname})

    num_events = random.randint(10, 50)
    events_data = []

    # 80% overlap
    overlap_count = int(num_events * 0.8)
    overlap_ids = random.sample(event_ids, min(overlap_count, len(event_ids)))

    other_ids = [str(uuid.uuid4()) for _ in range(num_events - len(overlap_ids))]
    all_event_ids = overlap_ids + other_ids
    random.shuffle(all_event_ids)

    for eid in all_event_ids:
        # Range -1.0 to 12.0
        ts = random.uniform(-1.0, 12.0)
        events_data.append({"event_id": eid, "timestamp_sec": f"{ts:.3f}"})

    return users_data, events_data

def test_fuzz_equivalence():
    assert os.path.exists(AGENT_SCRIPT), f"Agent script not found at {AGENT_SCRIPT}"
    assert os.path.exists(ORACLE_PATH), f"Oracle script not found at {ORACLE_PATH}"
    assert os.path.exists(VIDEO_PATH), f"Video not found at {VIDEO_PATH}"

    with tempfile.TemporaryDirectory() as tmpdir:
        for i in range(NUM_ITERATIONS):
            users_csv = os.path.join(tmpdir, f"users_{i}.csv")
            events_csv = os.path.join(tmpdir, f"events_{i}.csv")
            oracle_out = os.path.join(tmpdir, f"oracle_out_{i}.jsonl")
            agent_out = os.path.join(tmpdir, f"agent_out_{i}.jsonl")

            users_data, events_data = generate_fuzz_data(seed=i)

            with open(users_csv, "w", newline="") as f:
                writer = csv.DictWriter(f, fieldnames=["event_id", "username"])
                writer.writeheader()
                writer.writerows(users_data)

            with open(events_csv, "w", newline="") as f:
                writer = csv.DictWriter(f, fieldnames=["event_id", "timestamp_sec"])
                writer.writeheader()
                writer.writerows(events_data)

            # Run oracle
            subprocess.run(
                ["python3", ORACLE_PATH, VIDEO_PATH, users_csv, events_csv, oracle_out],
                check=True
            )

            # Run agent
            agent_res = subprocess.run(
                ["python3", AGENT_SCRIPT, VIDEO_PATH, users_csv, events_csv, agent_out],
                capture_output=True, text=True
            )
            assert agent_res.returncode == 0, f"Agent script failed on iteration {i}:\n{agent_res.stderr}"

            assert os.path.exists(agent_out), f"Agent did not produce output file {agent_out}"

            with open(oracle_out, "r") as f:
                oracle_lines = [json.loads(line) for line in f if line.strip()]

            with open(agent_out, "r") as f:
                agent_lines = [json.loads(line) for line in f if line.strip()]

            assert oracle_lines == agent_lines, (
                f"Output mismatch on iteration {i}.\n"
                f"Oracle: {oracle_lines}\n"
                f"Agent:  {agent_lines}"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
