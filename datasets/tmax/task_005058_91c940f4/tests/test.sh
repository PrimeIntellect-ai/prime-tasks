#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import string
import subprocess
import pytest

AGENT_PATH = "/home/user/graph_analyzer.sh"
DFS_PATH = "/app/sh-graph-tools/src/dfs.sh"
NUM_TESTS = 100


def generate_random_string(length=5):
    return ''.join(random.choices(string.ascii_letters + string.digits, k=length))


def generate_random_graph():
    num_nodes = random.randint(50, 500)
    nodes = [generate_random_string() for _ in range(num_nodes)]
    edges = []

    for node in nodes:
        num_out_edges = random.randint(2, 10)
        targets = random.choices(nodes, k=num_out_edges)
        for target in targets:
            edges.append(f"{node} {target}")

    return "\n".join(edges), random.choice(nodes)


def expected_output(graph_content, start_node):
    adjacency = {}
    indegree = {}

    for line in graph_content.splitlines():
        source, target = line.split()
        adjacency.setdefault(source, []).append(target)
        indegree[target] = indegree.get(target, 0) + 1

    visited = {start_node}
    queue = [start_node]
    head = 0
    while head < len(queue):
        current = queue[head]
        head += 1
        for neighbor in adjacency.get(current, []):
            if neighbor not in visited:
                visited.add(neighbor)
                queue.append(neighbor)

    ranked = sorted(visited, key=lambda node: (-indegree.get(node, 0), node))[:10]
    return ''.join(
        f"Node: {node}, InDegree: {indegree.get(node, 0)}\n"
        for node in ranked
    )


def test_agent_script_exists_and_executable():
    assert os.path.isfile(AGENT_PATH), f"Agent script {AGENT_PATH} does not exist."
    assert os.access(AGENT_PATH, os.X_OK), f"Agent script {AGENT_PATH} is not executable."


def test_makefile_fixed():
    result = subprocess.run(["make", "install"], cwd="/app/sh-graph-tools", capture_output=True)
    assert result.returncode == 0, f"make install failed:\nSTDOUT:\n{result.stdout.decode()}\nSTDERR:\n{result.stderr.decode()}"
    assert os.path.isfile("/app/sh-graph-tools/bin/dfs.sh"), "/app/sh-graph-tools/bin/dfs.sh does not exist after make install."
    assert os.access("/app/sh-graph-tools/bin/dfs.sh", os.X_OK), "/app/sh-graph-tools/bin/dfs.sh is not executable."


def test_dfs_handles_cycles():
    graph_file = "/tmp/dfs_cycle_graph.txt"
    with open(graph_file, "w") as f:
        f.write("A B\nB C\nC A\nC D\nB D\n")

    try:
        result = subprocess.run(
            [DFS_PATH, graph_file, "A"],
            capture_output=True,
            text=True,
            timeout=3,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("src/dfs.sh did not terminate on a cyclic graph")

    assert result.returncode == 0, f"src/dfs.sh failed:\nSTDERR:\n{result.stderr}"
    output_nodes = [line.strip() for line in result.stdout.splitlines() if line.strip()]
    assert set(output_nodes) == {"A", "B", "C", "D"}, f"Unexpected reachable nodes: {output_nodes}"
    assert len(output_nodes) == len(set(output_nodes)), f"src/dfs.sh emitted duplicate visited nodes: {output_nodes}"


def test_fuzz_equivalence():
    random.seed(42)

    for i in range(NUM_TESTS):
        graph_content, start_node = generate_random_graph()
        input_file = f"/tmp/fuzz_graph_{i}.txt"
        with open(input_file, "w") as f:
            f.write(graph_content)

        expected = expected_output(graph_content, start_node)
        agent_result = subprocess.run(
            [AGENT_PATH, input_file, start_node],
            capture_output=True,
            text=True,
        )

        if expected != agent_result.stdout:
            error_msg = f"Output mismatch on test {i} (start node: {start_node}).\n"
            error_msg += f"Expected output:\n{expected}\n"
            error_msg += f"Agent output:\n{agent_result.stdout}\n"
            error_msg += f"Agent stderr:\n{agent_result.stderr}\n"
            pytest.fail(error_msg)

        os.remove(input_file)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
