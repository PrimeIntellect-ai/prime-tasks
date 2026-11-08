#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import random
import string
import subprocess
import csv
import stat

def test_path_query_exists_and_executable():
    path = "/home/user/path_query"
    assert os.path.isfile(path), f"Executable {path} not found."
    assert os.access(path, os.X_OK), f"File {path} is not executable."

def test_fuzz_equivalence():
    oracle = "/tests/oracle_query"
    agent = "/home/user/path_query"

    # Ensure oracle is executable
    st = os.stat(oracle)
    os.chmod(oracle, st.st_mode | stat.S_IEXEC)

    # Get known vehicle IDs from the dataset to ensure positive hits
    known_vehicles = set()
    csv_path = "/home/user/raw_events.csv"
    if os.path.isfile(csv_path):
        with open(csv_path, "r", encoding="utf-8") as f:
            reader = csv.DictReader(f)
            if "vehicle_id" in reader.fieldnames:
                for row in reader:
                    known_vehicles.add(row["vehicle_id"])

    known_vehicles = list(known_vehicles)

    random.seed(42)
    inputs = []

    # Add a subset of known vehicles
    if known_vehicles:
        num_known = min(200, len(known_vehicles))
        inputs.extend(random.sample(known_vehicles, num_known))

    # Generate random strings of length 4 to 8
    chars = string.ascii_letters + string.digits
    while len(inputs) < 1000:
        length = random.randint(4, 8)
        inputs.append("".join(random.choices(chars, k=length)))

    random.shuffle(inputs)

    for val in inputs:
        oracle_res = subprocess.run([oracle, val], capture_output=True, text=True)
        agent_res = subprocess.run([agent, val], capture_output=True, text=True)

        oracle_out = oracle_res.stdout.strip()
        agent_out = agent_res.stdout.strip()

        assert oracle_out == agent_out, (
            f"Output mismatch for input '{val}'.\n"
            f"Oracle output: {oracle_out}\n"
            f"Agent output:  {agent_out}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
