#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import string
import subprocess
import pytest
import json

def generate_valid_dag_url():
    num_nodes = random.randint(3, 10)
    node_names = random.sample(string.ascii_uppercase, num_nodes)

    nodes_param = []
    for name in node_names:
        ts = round(random.uniform(0.0, 4.9), 2)
        nodes_param.append(f"{name}:{ts}")

    edges_param = []
    for i in range(num_nodes):
        for j in range(i + 1, num_nodes):
            if random.random() < 0.3:
                edges_param.append(f"{node_names[i]}->{node_names[j]}")

    url = f"https://ci.local/build/trigger?video=/app/pipeline_test.mp4&nodes={','.join(nodes_param)}"
    if edges_param:
        url += f"&edges={','.join(edges_param)}"
    return url

def generate_cycle_url():
    url = generate_valid_dag_url()
    # Add a cycle manually
    # Just append an edge from the last node to the first node
    parts = url.split("&edges=")
    if len(parts) == 2:
        nodes_str = url.split("&nodes=")[1].split("&")[0]
        node_names = [n.split(":")[0] for n in nodes_str.split(",")]
        cycle_edge = f"{node_names[-1]}->{node_names[0]}"
        return f"{parts[0]}&edges={parts[1]},{cycle_edge}"
    else:
        nodes_str = url.split("&nodes=")[1]
        node_names = [n.split(":")[0] for n in nodes_str.split(",")]
        cycle_edge = f"{node_names[-1]}->{node_names[0]}"
        return f"{url}&edges={cycle_edge}"

def generate_path_traversal_url():
    url = generate_valid_dag_url()
    return url.replace("/app/pipeline_test.mp4", "/app/../etc/passwd")

def generate_invalid_schema_url():
    url = generate_valid_dag_url()
    return url.replace("https://", "http://")

def generate_invalid_domain_url():
    url = generate_valid_dag_url()
    return url.replace("ci.local", "evil.local")

def generate_fuzz_inputs(n=200):
    random.seed(42)
    inputs = []
    for _ in range(n):
        r = random.random()
        if r < 0.6:
            inputs.append(generate_valid_dag_url())
        elif r < 0.7:
            inputs.append(generate_cycle_url())
        elif r < 0.8:
            inputs.append(generate_path_traversal_url())
        elif r < 0.9:
            inputs.append(generate_invalid_schema_url())
        else:
            inputs.append(generate_invalid_domain_url())
    return inputs

def run_script(script_cmd, arg):
    try:
        result = subprocess.run(
            script_cmd + [arg],
            capture_output=True,
            text=True,
            timeout=10
        )
        return result.stdout.strip()
    except subprocess.TimeoutExpired:
        return '{"status": "timeout"}'
    except Exception as e:
        return f'{{"status": "error", "msg": "{str(e)}"}}'

def test_fuzz_equivalence():
    oracle_script = ["python3", "/tests/oracle_router.py"]
    agent_script = ["python3", "/home/user/safe_router.py"]

    assert os.path.exists("/home/user/safe_router.py"), "Agent script /home/user/safe_router.py not found"
    assert os.path.exists("/tests/oracle_router.py"), "Oracle script /tests/oracle_router.py not found"

    inputs = generate_fuzz_inputs(200)

    for idx, inp in enumerate(inputs):
        oracle_out = run_script(oracle_script, inp)
        agent_out = run_script(agent_script, inp)

        try:
            oracle_json = json.loads(oracle_out)
        except json.JSONDecodeError:
            oracle_json = {"raw": oracle_out}

        try:
            agent_json = json.loads(agent_out)
        except json.JSONDecodeError:
            agent_json = {"raw": agent_out}

        assert oracle_json == agent_json, (
            f"Mismatch on input {idx}:\n"
            f"URL: {inp}\n"
            f"Oracle output: {oracle_out}\n"
            f"Agent output: {agent_out}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
