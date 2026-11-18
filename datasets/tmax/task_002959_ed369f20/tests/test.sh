#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import random
import subprocess
import sys
from pathlib import Path

def test_file_renaming():
    # Check that data1.dat and data2.dat were renamed to .car
    assert os.path.isfile("/app/incoming/data1.car"), "data1.car is missing. It should have been renamed from data1.dat."
    assert os.path.isfile("/app/incoming/data2.car"), "data2.car is missing. It should have been renamed from data2.dat."
    assert not os.path.isfile("/app/incoming/data1.dat"), "data1.dat still exists, it should have been renamed."
    assert not os.path.isfile("/app/incoming/data2.dat"), "data2.dat still exists, it should have been renamed."

    # Check that old.dat was NOT renamed
    assert os.path.isfile("/app/incoming/old.dat"), "old.dat is missing. It should NOT have been renamed because it is older than 7 days."
    assert not os.path.isfile("/app/incoming/old.car"), "old.car exists. old.dat should NOT have been renamed."

def generate_random_paths(num_paths):
    segments = ["foo", "bar", "..", ".", "/", "baz.txt", "../../", "etc", "passwd", "app", "safe_zone"]
    paths = []
    for _ in range(num_paths):
        path_length = random.randint(1, 10)
        path = "".join(random.choice(segments) for _ in range(path_length))
        paths.append({"path": path})
    return paths

def test_fuzz_equivalence():
    agent_script = "/home/user/safe_manifest_parser.py"
    oracle_script = "/tests/oracle_parser.py"

    assert os.path.isfile(agent_script), f"Agent script {agent_script} is missing."
    assert os.path.isfile(oracle_script), f"Oracle script {oracle_script} is missing."

    random.seed(42)

    for i in range(500):
        num_items = random.randint(0, 50)
        input_data = generate_random_paths(num_items)
        input_json = json.dumps(input_data)

        # Run oracle
        oracle_proc = subprocess.run(
            [sys.executable, oracle_script],
            input=input_json,
            text=True,
            capture_output=True
        )

        # Run agent
        agent_proc = subprocess.run(
            [sys.executable, agent_script],
            input=input_json,
            text=True,
            capture_output=True
        )

        # Compare outputs
        oracle_out = oracle_proc.stdout
        agent_out = agent_proc.stdout

        if oracle_out != agent_out:
            error_msg = (
                f"Mismatch on iteration {i}.\n"
                f"Input JSON:\n{input_json}\n\n"
                f"Expected Output (Oracle):\n{oracle_out}\n"
                f"Actual Output (Agent):\n{agent_out}\n"
            )
            assert False, error_msg
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
