#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import random
import subprocess
from collections import deque

DB_PATH = "/home/user/graph_db/nodes"
SCRIPT_PATH = "/home/user/etl_pipeline.sh"
REPORT_PATH = "/home/user/etl_report.txt"


def compute_expected(start_node="node_0", end_node="node_49", db_path=DB_PATH):
    def load_node(node_id):
        path = os.path.join(db_path, f"{node_id}.json")
        if not os.path.isfile(path):
            return {"id": node_id, "weight": 0, "linked_nodes": []}
        with open(path) as f:
            return json.load(f)

    visited = set()
    queue = deque([(start_node, 0)])
    shortest_hops = -1
    reachable_nodes = []

    while queue:
        curr, hops = queue.popleft()
        if curr not in visited:
            visited.add(curr)
            node_data = load_node(curr)
            reachable_nodes.append(node_data)

            if curr == end_node and shortest_hops == -1:
                shortest_hops = hops

            for neighbor in node_data.get("linked_nodes", []):
                if neighbor not in visited:
                    queue.append((neighbor, hops + 1))

    total_weight = sum(n.get("weight", 0) for n in reachable_nodes)

    filtered = [n for n in reachable_nodes if n.get("weight", 0) >= 20]
    filtered.sort(key=lambda x: (-x.get("weight", 0), x.get("id", "")))
    top_3 = [n["id"] for n in filtered[:3]]

    return shortest_hops, total_weight, ", ".join(top_3)


def read_report():
    assert os.path.isfile(REPORT_PATH), f"Report {REPORT_PATH} does not exist. Did you execute the script?"
    with open(REPORT_PATH, "r") as f:
        content = f.read().strip()
        lines = [line.strip() for line in content.split('\n')]
    assert len(lines) == 3, f"Report should have exactly 3 lines, but found {len(lines)} lines."
    return lines


def assert_report(start_node, end_node):
    lines = read_report()
    expected_hops, expected_weight, expected_top3 = compute_expected(start_node, end_node)
    assert lines[0] == str(expected_hops), f"Line 1 for {start_node} -> {end_node} is incorrect. Expected '{expected_hops}', got '{lines[0]}'."
    assert lines[1] == str(expected_weight), f"Line 2 for start {start_node} is incorrect. Expected '{expected_weight}', got '{lines[1]}'."
    assert lines[2] == expected_top3, f"Line 3 for start {start_node} is incorrect. Expected '{expected_top3}', got '{lines[2]}'."


def test_etl_pipeline_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."


def test_etl_report_contents():
    assert_report("node_0", "node_49")


def test_etl_pipeline_executes_and_is_parameterized():
    node_ids = sorted(
        os.path.splitext(name)[0]
        for name in os.listdir(DB_PATH)
        if name.endswith(".json") and os.path.isfile(os.path.join(DB_PATH, name))
    )
    assert node_ids, "Graph database contains no nodes."

    queries = [
        ("node_0", "node_49"),
        ("node_0", "node_0"),
        ("node_47", "node_49"),
        ("node_47", "node_48"),
        ("node_48", "node_47"),
    ]
    existing = set(queries)
    candidates = [(s, e) for s in node_ids for e in node_ids if s != e and (s, e) not in existing]
    queries.extend(random.SystemRandom().sample(candidates, min(7, len(candidates))))

    for start_node, end_node in queries:
        if os.path.exists(REPORT_PATH):
            os.remove(REPORT_PATH)
        result = subprocess.run(
            [SCRIPT_PATH, start_node, end_node],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, (
            f"Pipeline failed for {start_node} -> {end_node} with exit code {result.returncode}. "
            f"stdout: {result.stdout!r}; stderr: {result.stderr!r}"
        )
        assert_report(start_node, end_node)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
