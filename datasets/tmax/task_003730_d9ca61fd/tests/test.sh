#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import random
import subprocess

def test_blue_frames_count():
    path = "/home/user/blue_frames.txt"
    assert os.path.isfile(path), f"File {path} does not exist. The blue frames count was not saved."
    with open(path, "r") as f:
        content = f.read().strip()
    assert content == "14", f"Expected blue frames count to be '14', but got '{content}'."

def test_dedup_fuzz_equivalence():
    agent_script = "/home/user/dedup.py"
    oracle_script = "/tests/oracle_dedup.py"

    assert os.path.isfile(agent_script), f"Agent script {agent_script} not found."
    assert os.path.isfile(oracle_script), f"Oracle script {oracle_script} not found."

    random.seed(42)
    inputs = []

    hosts = ["hostA", "hostB", "hostC", "hostD"]
    keys = ["Mem", "Cpu", "disk", "net", "gpu"]

    # Generate 500 lines of input
    for _ in range(500):
        if random.random() < 0.1:
            # 10% invalid JSON
            inputs.append("INVALID JSON { \"bad\": " + str(random.randint(0, 100)))
        else:
            # 90% valid JSON
            config_parts = []
            for k in random.sample(keys, random.randint(1, len(keys))):
                if k == "Mem":
                    val = f"{random.randint(2, 16)}G"
                elif k == "Cpu":
                    val = str(random.randint(1, 8))
                else:
                    val = str(random.randint(10, 100))
                config_parts.append(f"{k}={val}")

            record = {
                "timestamp": f"2023-10-01T12:00:{random.randint(10,59)}Z",
                "host": random.choice(hosts),
                "config": ",".join(config_parts),
                "is_retry": random.choice([True, False])
            }
            inputs.append(json.dumps(record))

    input_data = "\n".join(inputs) + "\n"

    agent_proc = subprocess.run(["python3", agent_script], input=input_data, text=True, capture_output=True)
    oracle_proc = subprocess.run(["python3", oracle_script], input=input_data, text=True, capture_output=True)

    assert agent_proc.stdout == oracle_proc.stdout, (
        "Agent standard output does not match oracle standard output.\n"
        f"Oracle stdout snippet:\n{oracle_proc.stdout[:500]}\n"
        f"Agent stdout snippet:\n{agent_proc.stdout[:500]}"
    )

    assert agent_proc.stderr == oracle_proc.stderr, (
        "Agent standard error does not match oracle standard error.\n"
        f"Oracle stderr snippet:\n{oracle_proc.stderr[:500]}\n"
        f"Agent stderr snippet:\n{agent_proc.stderr[:500]}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
