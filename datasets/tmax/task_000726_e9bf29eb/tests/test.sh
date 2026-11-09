#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import random
import string
import subprocess
import pytest

def test_perturbation_fixed():
    dag_file = '/app/vendored/networkx-2.8.8/networkx/algorithms/dag.py'
    assert os.path.exists(dag_file), f"{dag_file} does not exist"
    with open(dag_file, 'r') as f:
        content = f.read()
    assert 'raise_syntax_error_here()' not in content, "Perturbation in dag.py was not fixed"

def generate_random_dag():
    num_tasks = random.randint(5, 25)
    tasks = {}
    task_names = []

    # Generate unique task names
    while len(task_names) < num_tasks:
        name = ''.join(random.choices(string.ascii_letters, k=random.randint(3, 8)))
        if name not in tasks:
            task_names.append(name)
            tasks[name] = {"cost": random.randint(1, 20)}

    dependencies = []
    # To guarantee a valid DAG, we impose a topological order
    for i in range(num_tasks):
        for j in range(i + 1, num_tasks):
            if random.random() < 0.3: # 30% chance of an edge
                dependencies.append([task_names[i], task_names[j]])

    max_cost = random.randint(20, 50)

    return json.dumps({
        "tasks": tasks,
        "dependencies": dependencies,
        "max_cost_per_batch": max_cost
    })

def test_fuzz_equivalence():
    oracle_path = '/tests/oracle_planner.py'
    agent_path = '/home/user/request_planner.py'

    assert os.path.exists(oracle_path), f"Oracle not found at {oracle_path}"
    assert os.path.exists(agent_path), f"Agent script not found at {agent_path}"

    random.seed(42)

    for i in range(100):
        input_json = generate_random_dag()

        # Run oracle
        oracle_cmd = ['python3', oracle_path, input_json]
        try:
            oracle_res = subprocess.run(oracle_cmd, capture_output=True, text=True, timeout=5)
            oracle_output = oracle_res.stdout.strip()
        except subprocess.TimeoutExpired:
            pytest.fail("Oracle timed out.")

        # Run agent
        agent_cmd = ['python3', agent_path, input_json]
        try:
            agent_res = subprocess.run(agent_cmd, capture_output=True, text=True, timeout=5)
            agent_output = agent_res.stdout.strip()
        except subprocess.TimeoutExpired:
            pytest.fail("Agent script timed out.")

        assert agent_res.returncode == 0, f"Agent script failed with error:\n{agent_res.stderr}\nInput: {input_json}"
        assert oracle_res.returncode == 0, f"Oracle script failed with error:\n{oracle_res.stderr}\nInput: {input_json}"

        assert agent_output == oracle_output, (
            f"Mismatch on iteration {i}.\n"
            f"Input:\n{input_json}\n\n"
            f"Expected (Oracle):\n{oracle_output}\n\n"
            f"Got (Agent):\n{agent_output}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
