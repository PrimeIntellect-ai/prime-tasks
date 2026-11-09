#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import subprocess
import uuid
from collections import deque


def test_script_exists_and_executable():
    """Verify that the analyze_deps.sh script exists and is executable."""
    script_path = '/home/user/analyze_deps.sh'
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."


def test_critical_path_output():
    """Verify that the critical_path.txt file contains the correct shortest path."""
    output_path = '/home/user/critical_path.txt'
    assert os.path.isfile(output_path), f"Output file {output_path} does not exist."

    with open(output_path, 'r') as f:
        content = f.read().strip()

    expected = "extract_users->fast_track_load->aggregate_metrics->report_generation"
    assert content == expected, f"Content of {output_path} is incorrect. Expected '{expected}', got '{content}'."


def test_script_functionality():
    """Verify that the script correctly computes the shortest path for a different set of inputs."""
    script_path = '/home/user/analyze_deps.sh'

    if not (os.path.isfile(script_path) and os.access(script_path, os.X_OK)):
        return  # Skip if script doesn't exist or isn't executable (handled by previous test)

    result = subprocess.run(
        [script_path, 'extract_users', 'aggregate_metrics'],
        capture_output=True,
        text=True
    )

    assert result.returncode == 0, f"Script failed to execute successfully. Stderr: {result.stderr}"

    output = result.stdout.strip()
    expected = "extract_users->fast_track_load->aggregate_metrics"
    assert output == expected, f"Script output incorrect for 'extract_users' to 'aggregate_metrics'. Expected '{expected}', got '{output}'."


def shortest_distance(edges, start, end):
    graph = {}
    for upstream, downstream in edges:
        graph.setdefault(upstream, []).append(downstream)

    queue = deque([(start, 0)])
    seen = {start}
    while queue:
        node, distance = queue.popleft()
        if node == end:
            return distance
        for neighbor in graph.get(node, []):
            if neighbor not in seen:
                seen.add(neighbor)
                queue.append((neighbor, distance + 1))
    return None


def test_arbitrary_job_pairs_from_dependency_file():
    """Exercise multiple unpredictable pairs against a temporary dependency graph."""
    script_path = '/home/user/analyze_deps.sh'
    csv_path = '/home/user/etl_dependencies.csv'

    with open(csv_path, 'rb') as f:
        original_csv = f.read()

    token = uuid.uuid4().hex
    nodes = {name: f"job_{token}_{name}" for name in (
        'start', 'a', 'b', 'c', 'd', 'e', 'target',
        'upper', 'v', 'w', 'x', 'other', 'r'
    )}

    edges = [
        (nodes['start'], nodes['a']),
        (nodes['a'], nodes['b']),
        (nodes['b'], nodes['target']),
        (nodes['start'], nodes['c']),
        (nodes['c'], nodes['d']),
        (nodes['d'], nodes['e']),
        (nodes['e'], nodes['target']),
        (nodes['a'], nodes['d']),
        (nodes['upper'], nodes['v']),
        (nodes['v'], nodes['target']),
        (nodes['upper'], nodes['w']),
        (nodes['w'], nodes['x']),
        (nodes['x'], nodes['target']),
        (nodes['other'], nodes['r']),
        (nodes['r'], nodes['x']),
    ]
    random.SystemRandom().shuffle(edges)

    queries = [
        (nodes['start'], nodes['target']),
        (nodes['a'], nodes['target']),
        (nodes['upper'], nodes['target']),
        (nodes['other'], nodes['target']),
    ]
    edge_set = set(edges)

    try:
        with open(csv_path, 'w', newline='') as f:
            for upstream, downstream in edges:
                f.write(f"{upstream},{downstream}\n")

        for start, end in queries:
            result = subprocess.run(
                [script_path, start, end],
                capture_output=True,
                text=True,
                timeout=10,
            )
            assert result.returncode == 0, (
                f"Script failed for arbitrary pair {start!r} to {end!r}. "
                f"Stderr: {result.stderr}"
            )

            output = result.stdout.strip()
            path = output.split('->') if output else []
            assert path and path[0] == start and path[-1] == end, (
                f"Output is not a path from {start!r} to {end!r}: {output!r}"
            )
            assert all((upstream, downstream) in edge_set
                       for upstream, downstream in zip(path, path[1:])), (
                f"Output uses an edge absent from the CSV: {output!r}"
            )

            expected_distance = shortest_distance(edges, start, end)
            assert expected_distance is not None
            assert len(path) - 1 == expected_distance, (
                f"Path is not shortest for {start!r} to {end!r}: {output!r}; "
                f"expected {expected_distance} edges"
            )
    finally:
        with open(csv_path, 'wb') as f:
            f.write(original_csv)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
