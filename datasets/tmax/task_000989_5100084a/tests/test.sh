#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import random
import subprocess
import pytest

def generate_random_json(num_nodes):
    papers = []
    # Sample unique IDs
    ids = random.sample(range(1, 1001), num_nodes)
    for pid in ids:
        year = random.randint(1990, 2024)
        num_cites = random.randint(0, min(10, num_nodes - 1))
        # Cites can be any subset of the existing IDs
        cites = random.sample(ids, num_cites)
        if pid in cites:
            cites.remove(pid)
        papers.append({
            "id": pid,
            "year": year,
            "cites": cites
        })
    return json.dumps({"papers": papers})

def test_libdataset_compiled():
    assert os.path.isfile('/app/libdataset/libdataset.a'), "libdataset.a was not compiled. The Makefile perturbation may not have been fixed."

def test_process_compiled():
    agent_path = '/home/user/process'
    assert os.path.isfile(agent_path), f"{agent_path} executable is missing. Did you compile your C++ program?"
    assert os.access(agent_path, os.X_OK), f"{agent_path} is not executable."

def test_fuzz_equivalence():
    random.seed(42)
    oracle_path = '/tests/oracle_graph_query'
    agent_path = '/home/user/process'

    assert os.path.isfile(oracle_path), "Oracle program missing."
    assert os.access(oracle_path, os.X_OK), "Oracle program not executable."

    for i in range(50):
        num_nodes = random.randint(10, 100)
        json_input = generate_random_json(num_nodes)
        min_year = random.randint(2000, 2020)

        oracle_proc = subprocess.run(
            [oracle_path, str(min_year)],
            input=json_input,
            text=True,
            capture_output=True
        )

        agent_proc = subprocess.run(
            [agent_path, str(min_year)],
            input=json_input,
            text=True,
            capture_output=True
        )

        assert agent_proc.returncode == 0, f"Agent program failed with return code {agent_proc.returncode}\nStderr: {agent_proc.stderr}\nInput: {json_input}"

        oracle_output = oracle_proc.stdout.strip()
        agent_output = agent_proc.stdout.strip()

        if oracle_output != agent_output:
            pytest.fail(
                f"Mismatch on fuzz iteration {i}.\n"
                f"min_year: {min_year}\n"
                f"Input JSON: {json_input}\n\n"
                f"Oracle output:\n{oracle_output}\n\n"
                f"Agent output:\n{agent_output}"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
