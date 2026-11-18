#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import stat
import sys

EXPECTED_TEST_DAG = b'''from dag import resolve_dependencies
import pytest

def test_linear():
    graph = {'A': ['B'], 'B': ['C'], 'C': []}
    assert resolve_dependencies(graph) == ['C', 'B', 'A']

def test_diamond():
    # A depends on B and C, which both depend on D
    graph = {'A': ['B', 'C'], 'B': ['D'], 'C': ['D'], 'D': []}
    result = resolve_dependencies(graph)
    assert result.index('D') < result.index('B')
    assert result.index('D') < result.index('C')
    assert result.index('B') < result.index('A')
    assert result.index('C') < result.index('A')

def test_cycle():
    graph = {'A': ['B'], 'B': ['C'], 'C': ['A']}
    with pytest.raises(ValueError, match="Cycle detected"):
        resolve_dependencies(graph)
'''


def get_resolver():
    sys.path.insert(0, '/home/user/project')
    try:
        from dag import resolve_dependencies
    except ImportError:
        assert False, "Could not import resolve_dependencies from /home/user/project/dag.py"
    return resolve_dependencies


def test_success_log():
    log_path = '/home/user/success.log'
    assert os.path.isfile(log_path), f"Expected success log at {log_path} is missing."
    with open(log_path, 'r') as f:
        content = f.read().strip()
    assert content == "ALL TESTS PASSED", f"Expected success log to contain 'ALL TESTS PASSED', got '{content}'"


def test_test_dag_unchanged():
    path = '/home/user/project/test_dag.py'
    info = os.lstat(path)
    assert stat.S_ISREG(info.st_mode), "test_dag.py must remain a regular file"
    with open(path, 'rb') as f:
        actual = f.read()
    assert actual == EXPECTED_TEST_DAG, "test_dag.py was modified"


def test_dag_logic():
    resolve_dependencies = get_resolver()

    # Test Linear
    graph_linear = {'A': ['B'], 'B': ['C'], 'C': []}
    assert resolve_dependencies(graph_linear) == ['C', 'B', 'A'], "Linear dependency resolution failed."

    # Test Diamond (This tests if the recursion stack state bug was fixed)
    graph_diamond = {'A': ['B', 'C'], 'B': ['D'], 'C': ['D'], 'D': []}
    try:
        result = resolve_dependencies(graph_diamond)
    except ValueError as e:
        assert False, f"Diamond dependency resolution failed with ValueError: {e}. The DFS recursion stack state (visiting) might not be properly managed."

    assert result.index('D') < result.index('B'), "Diamond dependency resolution order incorrect (D must precede B)."
    assert result.index('D') < result.index('C'), "Diamond dependency resolution order incorrect (D must precede C)."
    assert result.index('B') < result.index('A'), "Diamond dependency resolution order incorrect (B must precede A)."
    assert result.index('C') < result.index('A'), "Diamond dependency resolution order incorrect (C must precede A)."

    # Test Cycle (This tests if the patch was applied correctly)
    graph_cycle = {'A': ['B'], 'B': ['C'], 'C': ['A']}
    cycle_detected = False
    try:
        resolve_dependencies(graph_cycle)
    except ValueError as e:
        if "Cycle detected" in str(e):
            cycle_detected = True

    assert cycle_detected, "Cycle dependency was not detected. The patch might not have been applied or the ValueError message is incorrect."


def test_general_dag_and_cycle_detection():
    resolve_dependencies = get_resolver()
    rng = random.SystemRandom()

    # Exercise unpredictable DAG shapes and verify the result from graph invariants.
    for _ in range(30):
        count = rng.randrange(6, 16)
        nodes = [secrets.token_hex(12) for _ in range(count)]
        graph = {}
        for i, node in enumerate(nodes):
            possible = nodes[:i]
            deps = [dep for dep in possible if rng.random() < 0.35]
            rng.shuffle(deps)
            graph[node] = deps
        items = list(graph.items())
        rng.shuffle(items)
        graph = dict(items)

        result = resolve_dependencies(graph)
        assert isinstance(result, list), "Resolver must return an execution-order list"
        assert len(result) == len(nodes), "Resolver returned missing or duplicate nodes"
        assert set(result) == set(nodes), "Resolver returned the wrong set of nodes"
        positions = {node: i for i, node in enumerate(result)}
        for node, deps in graph.items():
            for dep in deps:
                assert positions[dep] < positions[node], f"Dependency {dep} must precede {node}"

    # Exercise unpredictable cycle sizes, labels, insertion orders, and surrounding nodes.
    for _ in range(20):
        cycle_size = rng.randrange(1, 11)
        cycle = [secrets.token_hex(12) for _ in range(cycle_size)]
        graph = {cycle[i]: [cycle[(i + 1) % cycle_size]] for i in range(cycle_size)}
        extras = [secrets.token_hex(12) for _ in range(rng.randrange(2, 8))]
        for i, node in enumerate(extras):
            deps = [dep for dep in extras[:i] if rng.random() < 0.4]
            if rng.random() < 0.5:
                deps.append(rng.choice(cycle))
            graph[node] = deps
        items = list(graph.items())
        rng.shuffle(items)
        graph = dict(items)

        try:
            resolve_dependencies(graph)
        except ValueError as exc:
            assert "Cycle detected" in str(exc), "Cycle error message must contain 'Cycle detected'"
        else:
            assert False, "A generated circular dependency was not detected"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /home/user/project/test_dag.py /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
