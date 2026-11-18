#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os

NODES_PATH = "/home/user/nodes.tsv"
EDGES_PATH = "/home/user/edges.tsv"
OUTPUT_PATH = "/home/user/admin_execute_stats.tsv"

EXPECTED_NODES = """1\tAlice_Sys\tAdmin
2\tBob_Dev\tDeveloper
3\tCharlie_Ops\tAdmin
4\tDave_Sec\tSecurity
5\tEve_Root\tAdmin
6\tFrank_Net\tAdmin
"""

EXPECTED_EDGES = """1\t2\tExecute
1\t3\tRead
1\t4\tExecute
3\t1\tExecute
3\t2\tExecute
3\t4\tExecute
3\t5\tExecute
5\t1\tRead
5\t2\tWrite
6\t1\tExecute
6\t2\tExecute
6\t3\tExecute
6\t4\tExecute
6\t5\tExecute
"""

def test_input_files_unchanged():
    """Ensure expected results cannot be altered by modifying the input files."""
    with open(NODES_PATH, "r") as f:
        assert f.read() == EXPECTED_NODES, f"Input file was modified: {NODES_PATH}"
    with open(EDGES_PATH, "r") as f:
        assert f.read() == EXPECTED_EDGES, f"Input file was modified: {EDGES_PATH}"

def test_admin_execute_stats_exists():
    """Check that /home/user/admin_execute_stats.tsv exists."""
    assert os.path.isfile(OUTPUT_PATH), f"Missing output file: {OUTPUT_PATH}"

def test_admin_execute_stats_content():
    """Compute the expected output from nodes and edges and verify the output file."""
    admin_nodes = {}
    with open(NODES_PATH, 'r') as f:
        for line in f:
            parts = line.strip('\n').split('\t')
            if len(parts) >= 3:
                node_id, entity_name, role = parts[0], parts[1], parts[2]
                if role == 'Admin':
                    admin_nodes[node_id] = entity_name

    execute_counts = {node_id: 0 for node_id in admin_nodes}
    with open(EDGES_PATH, 'r') as f:
        for line in f:
            parts = line.strip('\n').split('\t')
            if len(parts) >= 3:
                source_id, target_id, action_type = parts[0], parts[1], parts[2]
                if source_id in admin_nodes and action_type == 'Execute':
                    execute_counts[source_id] += 1

    results = []
    for node_id, count in execute_counts.items():
        if count > 0:
            results.append((admin_nodes[node_id], count))

    results.sort(key=lambda x: (-x[1], x[0]))
    expected_lines = [f"{entity}\t{count}" for entity, count in results]

    with open(OUTPUT_PATH, 'r') as f:
        actual_lines = [line.strip('\n') for line in f if line.strip('\n')]

    assert actual_lines == expected_lines, (
        f"Output file {OUTPUT_PATH} content does not match expected.\n"
        f"Expected:\n{chr(10).join(expected_lines)}\n"
        f"Actual:\n{chr(10).join(actual_lines)}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
