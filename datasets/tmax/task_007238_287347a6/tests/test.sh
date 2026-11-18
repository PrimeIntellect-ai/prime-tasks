#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import heapq
import pytest

ARTIFACTS_DIR = "/home/user/artifacts"
BUILD_ORDER_LOG = "/home/user/build_order.log"
FINAL_ARTIFACT_DAT = "/home/user/final_artifact.dat"

def get_expected_results():
    """
    Parses the actual artifacts directory to derive the correct topological sort
    and the final numerical state.
    """
    nodes = []
    dependencies = {}
    data_arrays = {}

    for filename in os.listdir(ARTIFACTS_DIR):
        if filename.endswith(".dat"):
            nodes.append(filename)
            filepath = os.path.join(ARTIFACTS_DIR, filename)
            with open(filepath, "r") as f:
                lines = f.read().splitlines()
                deps_line = lines[0]
                data_line = lines[1]

                if deps_line.startswith("DEPENDS:"):
                    deps_str = deps_line[len("DEPENDS:"):].strip()
                    deps = deps_str.split() if deps_str else []
                    dependencies[filename] = deps

                data_arrays[filename] = [int(x) for x in data_line.split()]

    # Build adjacency list (v -> u) and in-degrees
    adj = {node: [] for node in nodes}
    in_degree = {node: 0 for node in nodes}

    for u, deps in dependencies.items():
        for v in deps:
            adj[v].append(u)
            in_degree[u] += 1

    # Kahn's algorithm with priority queue for alphabetical tie-breaking
    queue = [n for n in nodes if in_degree[n] == 0]
    heapq.heapify(queue)

    topo_order = []
    while queue:
        curr = heapq.heappop(queue)
        topo_order.append(curr)
        for neighbor in adj[curr]:
            in_degree[neighbor] -= 1
            if in_degree[neighbor] == 0:
                heapq.heappush(queue, neighbor)

    # Compute the final state array
    state = [0] * 500
    for node in topo_order:
        for i in range(500):
            state[i] = (state[i] + data_arrays[node][i]) % 10007

    return topo_order, state

def test_build_order_log():
    """Check that build_order.log exists and contains the correct deterministic topological sort."""
    assert os.path.exists(BUILD_ORDER_LOG), f"Missing output file: {BUILD_ORDER_LOG}"

    expected_order, _ = get_expected_results()

    with open(BUILD_ORDER_LOG, "r") as f:
        actual_order = [line.strip() for line in f.read().splitlines() if line.strip()]

    assert actual_order == expected_order, "The build order in build_order.log does not match the expected deterministic topological sort."

def test_final_artifact_dat():
    """Check that final_artifact.dat exists and contains the correct merged numerical data."""
    assert os.path.exists(FINAL_ARTIFACT_DAT), f"Missing output file: {FINAL_ARTIFACT_DAT}"

    _, expected_state = get_expected_results()

    with open(FINAL_ARTIFACT_DAT, "r") as f:
        content = f.read().strip()

    try:
        actual_state = [int(x) for x in content.split()]
    except ValueError:
        pytest.fail(f"The file {FINAL_ARTIFACT_DAT} contains non-integer values.")

    assert len(actual_state) == 500, f"Expected exactly 500 integers in {FINAL_ARTIFACT_DAT}, but found {len(actual_state)}."
    assert actual_state == expected_state, "The merged state array in final_artifact.dat is incorrect."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
