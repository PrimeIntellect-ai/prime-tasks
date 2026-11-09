#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import heapq
import json
import os
import random
import subprocess
import tempfile
import pytest


def generate_graph(seed):
    random.seed(seed)
    n = random.randint(10, 50)
    p = random.uniform(0.1, 0.3)

    node_ids = random.sample(range(1, 1000), n)
    nodes = [{"id": nid, "size": random.randint(10, 1000)} for nid in node_ids]

    edges = []
    for i in node_ids:
        for j in node_ids:
            if i != j and random.random() < p:
                edges.append({
                    "source": i,
                    "target": j,
                    "transfer_time": random.randint(1, 20)
                })

    return {"nodes": nodes, "edges": edges}


def derive_expected(data):
    node_ids = [node["id"] for node in data["nodes"]]
    sizes = {node["id"]: node["size"] for node in data["nodes"]}

    # Match DiGraph semantics: repeated source/target pairs replace the weight
    # and contribute only once to in-degree.
    adjacency = {node_id: {} for node_id in node_ids}
    for edge in data["edges"]:
        adjacency[edge["source"]][edge["target"]] = edge["transfer_time"]

    indegree = {node_id: 0 for node_id in node_ids}
    for targets in adjacency.values():
        for target in targets:
            indegree[target] += 1

    roots = [node_id for node_id in node_ids if indegree[node_id] == 0]
    distances = {node_id: float("inf") for node_id in node_ids}
    queue = []
    for root in roots:
        distances[root] = 0
        heapq.heappush(queue, (0, root))

    while queue:
        distance, current = heapq.heappop(queue)
        if distance != distances[current]:
            continue
        for target, weight in adjacency[current].items():
            candidate = distance + weight
            if candidate < distances[target]:
                distances[target] = candidate
                heapq.heappush(queue, (candidate, target))

    scores = []
    for node_id in node_ids:
        distance = distances[node_id]
        if distance == float("inf"):
            distance = 0
        scores.append((sizes[node_id] * (1 + distance), node_id))

    scores.sort(key=lambda item: (-item[0], item[1]))
    return ",".join(str(node_id) for _, node_id in scores)


def test_fuzz_equivalence():
    agent_script = "/home/user/backup_planner.py"
    oracle_bin = "/app/backup_path_oracle"

    assert os.path.isfile(agent_script), f"Agent script not found at {agent_script}"
    assert os.path.isfile(oracle_bin), f"Oracle binary not found at {oracle_bin}"

    with tempfile.TemporaryDirectory() as tmpdir:
        cases = []
        for i in range(100):
            graph_data = generate_graph(i)
            input_path = os.path.join(tmpdir, f"graph_{i}.json")
            with open(input_path, "w") as f:
                json.dump(graph_data, f)

            expected = derive_expected(graph_data)

            # Preserve the original oracle-equivalence assertion, but perform it
            # before removing the oracle from the agent program's runtime.
            oracle_res = subprocess.run(
                [oracle_bin, input_path], capture_output=True, text=True
            )
            assert oracle_res.returncode == 0, (
                f"Oracle failed on input {i}:\n{oracle_res.stderr}"
            )
            oracle_out = oracle_res.stdout.strip()
            assert oracle_out == expected, (
                f"Independent expected result disagrees with oracle on input {i}.\n"
                f"Graph Data: {json.dumps(graph_data)}\n"
                f"Derived: {expected}\nOracle: {oracle_out}"
            )
            cases.append((i, graph_data, input_path, expected))

        # The oracle was available for reverse engineering during the task, but
        # must not be available to a submitted proxy when that proxy is tested.
        os.unlink(oracle_bin)
        assert not os.path.exists(oracle_bin)

        for i, graph_data, input_path, expected in cases:
            agent_res = subprocess.run(
                ["python3", agent_script, input_path],
                capture_output=True,
                text=True,
            )
            if agent_res.returncode != 0:
                pytest.fail(f"Agent script failed on input {i}:\n{agent_res.stderr}")

            agent_out = agent_res.stdout.strip()
            if expected != agent_out:
                pytest.fail(
                    f"Mismatch on random input {i} (seed {i}).\n"
                    f"Graph Data: {json.dumps(graph_data)}\n"
                    f"Expected: {expected}\n"
                    f"Got:      {agent_out}"
                )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
