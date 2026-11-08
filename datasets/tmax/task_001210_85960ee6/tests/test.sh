#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import string
import subprocess
import tempfile
from collections import defaultdict, deque

import pytest

SOURCE_PATH = "/home/user/kg_query.cpp"
AGENT_PATH = "/home/user/kg_query"
NUM_TESTS = 100


def generate_random_string(min_len=3, max_len=10):
    length = random.randint(min_len, max_len)
    return ''.join(random.choices(string.ascii_letters + string.digits, k=length))


def generate_csv_data(num_edges):
    relationships = ["depends_on", "includes", "conflicts", "replaces", "blocks", "triggers"]
    num_nodes = max(2, num_edges // 2)
    nodes = [generate_random_string() for _ in range(num_nodes)]

    edges = []
    sources = []
    for _ in range(num_edges):
        source = random.choice(nodes)
        target = random.choice(nodes)
        rel = random.choice(relationships)
        edges.append(f"{source},{target},{rel}")
        sources.append(source)

    csv_content = "\n".join(edges) + "\n"
    start_node = random.choice(sources)
    return csv_content, start_node


def expected_output(csv_content, start_node):
    graph = defaultdict(list)
    for line in csv_content.splitlines():
        if not line:
            continue
        parts = line.split(',', 2)
        if len(parts) == 3:
            source, target, rel = parts
            if rel == "depends_on" or rel == "includes":
                graph[source].append(target)

    visited = {start_node}
    reachable = set()
    queue = deque([start_node])
    while queue:
        current = queue.popleft()
        for neighbor in graph[current]:
            if neighbor not in visited:
                visited.add(neighbor)
                reachable.add(neighbor)
                queue.append(neighbor)

    return ''.join(node + "\n" for node in sorted(reachable))


def test_agent_source_exists():
    assert os.path.exists(SOURCE_PATH), f"Agent source not found at {SOURCE_PATH}"
    assert os.path.isfile(SOURCE_PATH), f"Path {SOURCE_PATH} is not a file"


def test_agent_executable_exists():
    assert os.path.exists(AGENT_PATH), f"Agent executable not found at {AGENT_PATH}"
    assert os.path.isfile(AGENT_PATH), f"Path {AGENT_PATH} is not a file"
    assert os.access(AGENT_PATH, os.X_OK), f"Agent executable {AGENT_PATH} is not executable"


def test_fuzz_equivalence():
    random.seed(42)

    with tempfile.TemporaryDirectory() as tmpdir:
        for i in range(NUM_TESTS):
            num_edges = random.randint(20, 500)
            csv_content, start_node = generate_csv_data(num_edges)

            csv_path = os.path.join(tmpdir, f"test_{i}.csv")
            with open(csv_path, "w") as f:
                f.write(csv_content)

            agent_cmd = [AGENT_PATH, csv_path, start_node]
            agent_res = subprocess.run(agent_cmd, capture_output=True, text=True)

            if agent_res.returncode != 0:
                pytest.fail(
                    f"Agent failed on test {i} (start node '{start_node}').\n"
                    f"Stderr: {agent_res.stderr}\nCSV content:\n{csv_content}"
                )

            oracle_out = expected_output(csv_content, start_node)
            agent_out = agent_res.stdout

            if oracle_out != agent_out:
                pytest.fail(
                    f"Mismatch on test {i} (start node '{start_node}').\n"
                    f"--- Expected (Oracle) ---\n{oracle_out}\n"
                    f"--- Actual (Agent) ---\n{agent_out}\n"
                    f"--- CSV Content ---\n{csv_content}"
                )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
