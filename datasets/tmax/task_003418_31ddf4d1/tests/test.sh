#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import json
import random
import subprocess
import tempfile
import pytest

WORDS = [
    "apple", "banana", "cherry", "date", "elderberry", "fig", "grape", "honeydew",
    "kiwi", "lemon", "mango", "nectarine", "orange", "papaya", "quince", "raspberry",
    "strawberry", "tangerine", "ugli", "vanilla", "watermelon", "xigua", "yam", "zucchini",
    "apricot", "blackberry", "blueberry", "cantaloupe", "dragonfruit", "grapefruit",
    "guava", "jackfruit", "kumquat", "lime", "lychee", "mandarin", "mulberry", "olive",
    "peach", "pear", "persimmon", "pineapple", "plum", "pomegranate", "pomelo", "starfruit",
    "tamarind", "yuzu", "coconut", "cranberry"
]

def generate_csv(path, seed, num_rows=100):
    random.seed(seed)
    with open(path, 'w', newline='', encoding='utf-8') as f:
        writer = csv.writer(f)
        writer.writerow(["id", "numeric_val", "text_data"])
        for i in range(num_rows):
            if random.random() < 0.05:
                val = random.choice([-10.0, 10.0])
            else:
                val = random.gauss(0, 2)

            words = [random.choice(WORDS) for _ in range(random.randint(1, 15))]
            text = " ".join(words)
            writer.writerow([i, val, text])

def test_pipeline_fuzz_equivalence():
    agent_script = "/home/user/pipeline.py"
    oracle_script = "/tests/oracle_pipeline.py"

    assert os.path.isfile(agent_script), f"Agent script not found at {agent_script}"
    assert os.path.isfile(oracle_script), f"Oracle script not found at {oracle_script}"

    num_iterations = 100

    with tempfile.TemporaryDirectory() as tmpdir:
        for i in range(num_iterations):
            input_csv = os.path.join(tmpdir, f"input_{i}.csv")
            agent_json = os.path.join(tmpdir, f"agent_output_{i}.json")
            oracle_json = os.path.join(tmpdir, f"oracle_output_{i}.json")

            generate_csv(input_csv, seed=42+i)

            # Run oracle
            oracle_res = subprocess.run(
                ["python3", oracle_script, input_csv, oracle_json],
                capture_output=True, text=True
            )
            assert oracle_res.returncode == 0, f"Oracle failed on iteration {i}:\n{oracle_res.stderr}"

            # Run agent
            agent_res = subprocess.run(
                ["python3", agent_script, input_csv, agent_json],
                capture_output=True, text=True
            )
            assert agent_res.returncode == 0, f"Agent script failed on iteration {i}:\n{agent_res.stderr}"

            assert os.path.isfile(oracle_json), f"Oracle output JSON missing on iteration {i}"
            assert os.path.isfile(agent_json), f"Agent output JSON missing on iteration {i}"

            with open(oracle_json, 'r', encoding='utf-8') as f:
                oracle_data = json.load(f)

            with open(agent_json, 'r', encoding='utf-8') as f:
                try:
                    agent_data = json.load(f)
                except json.JSONDecodeError:
                    pytest.fail(f"Agent output is not valid JSON on iteration {i}")

            # Compare the results
            assert len(oracle_data) == len(agent_data), f"Mismatch in number of rows output on iteration {i}. Expected {len(oracle_data)}, got {len(agent_data)}."

            for j, (o_row, a_row) in enumerate(zip(oracle_data, agent_data)):
                # Float comparison for numeric_val might have slight differences depending on precision,
                # but usually they match exactly or very closely
                for k in o_row.keys():
                    assert k in a_row, f"Missing key '{k}' in agent output row {j} on iteration {i}"
                    if isinstance(o_row[k], float):
                        assert abs(o_row[k] - a_row[k]) < 1e-5, f"Value mismatch for key '{k}' in row {j} on iteration {i}: Expected {o_row[k]}, got {a_row[k]}"
                    else:
                        assert o_row[k] == a_row[k], f"Value mismatch for key '{k}' in row {j} on iteration {i}: Expected {o_row[k]}, got {a_row[k]}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
