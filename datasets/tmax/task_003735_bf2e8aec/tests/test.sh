#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import csv
import random
import subprocess
import tempfile
import pytest

def test_extracted_graph_csv():
    extracted_path = "/home/user/extracted_graph.csv"
    assert os.path.isfile(extracted_path), f"Expected extracted CSV at {extracted_path} does not exist."

    expected_content = [
        ["node_id", "parent_id", "metric_value"],
        ["1", "0", "100"],
        ["2", "1", "50"],
        ["3", "1", "20"],
        ["4", "2", "10"],
        ["5", "2", "5"]
    ]

    with open(extracted_path, 'r') as f:
        reader = csv.reader(f)
        actual_content = [row for row in reader if row]

    assert actual_content == expected_content, f"Content of {extracted_path} does not match expected ground truth."

def generate_random_tree_csv(num_nodes):
    nodes = []
    nodes.append({'node_id': 1, 'parent_id': 0, 'metric_value': random.randint(0, 1000)})
    for i in range(2, num_nodes + 1):
        parent = random.randint(1, i - 1)
        nodes.append({'node_id': i, 'parent_id': parent, 'metric_value': random.randint(0, 1000)})

    ids = list(range(1, num_nodes + 1))
    random.shuffle(ids)
    id_map = {orig: new for orig, new in zip(range(1, num_nodes + 1), ids)}
    id_map[0] = 0

    shuffled_nodes = []
    for n in nodes:
        parent_val = id_map[n['parent_id']]
        if random.choice([True, False]) and parent_val == 0:
            parent_val = ""
        shuffled_nodes.append({
            'node_id': id_map[n['node_id']],
            'parent_id': parent_val,
            'metric_value': n['metric_value']
        })

    random.shuffle(shuffled_nodes)
    return shuffled_nodes

def test_aggregate_graph_fuzz_equivalence():
    agent_script = "/home/user/aggregate_graph.sh"
    oracle_script = "/tests/oracle_aggregate_graph.py"

    assert os.path.isfile(agent_script), f"Agent script {agent_script} does not exist."
    assert os.path.isfile(oracle_script), f"Oracle script {oracle_script} does not exist."

    random.seed(42)

    for i in range(100):
        num_nodes = random.randint(10, 500)
        tree_data = generate_random_tree_csv(num_nodes)

        with tempfile.NamedTemporaryFile(mode='w', delete=False, suffix='.csv') as tmp:
            writer = csv.DictWriter(tmp, fieldnames=['node_id', 'parent_id', 'metric_value'])
            writer.writeheader()
            writer.writerows(tree_data)
            tmp_path = tmp.name

        try:
            oracle_proc = subprocess.run(
                ["python3", oracle_script, tmp_path],
                capture_output=True, text=True, check=True
            )
            oracle_output = oracle_proc.stdout.strip()

            agent_proc = subprocess.run(
                ["/bin/bash", agent_script, tmp_path],
                capture_output=True, text=True
            )

            assert agent_proc.returncode == 0, f"Agent script failed with error:\n{agent_proc.stderr}"
            agent_output = agent_proc.stdout.strip()

            if oracle_output != agent_output:
                with open(tmp_path, 'r') as f:
                    input_csv = f.read()
                pytest.fail(
                    f"Mismatch found on iteration {i+1} with {num_nodes} nodes.\n\n"
                    f"Input CSV:\n{input_csv}\n\n"
                    f"Oracle Output:\n{oracle_output}\n\n"
                    f"Agent Output:\n{agent_output}"
                )
        finally:
            os.remove(tmp_path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
