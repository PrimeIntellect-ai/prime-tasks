#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import pathlib
import random
import secrets
import subprocess
import sys

import pytest


def test_reproducibility_passes():
    """Retain the original vendored regression-test assertion."""
    test_file = "/app/mcmc_graph_solver/tests/test_reproducibility.py"
    assert os.path.exists(test_file), f"Test file {test_file} is missing."

    result = subprocess.run(
        ["pytest", test_file],
        capture_output=True,
        text=True
    )
    assert result.returncode == 0, f"Reproducibility test failed. The matrix construction is likely still non-deterministic.\nPytest Output:\n{result.stdout}\n{result.stderr}"


def test_core_is_installed_editably_and_deterministic():
    """Check the package itself rather than trusting its mutable test file."""
    token = secrets.token_hex(8)
    nodes = [f"node_{token}_{i:02d}" for i in range(24)]
    shuffled = list(nodes)
    random.SystemRandom().shuffle(shuffled)
    edges = []
    for i, node in enumerate(shuffled):
        edges.append((node, shuffled[(i + 1) % len(shuffled)]))
        edges.append((node, shuffled[(i + 5) % len(shuffled)]))
    edges.extend(edges[:7])
    expected = sorted(set(node for edge in edges for node in edge))

    check_code = r'''
import importlib.metadata
import inspect
import json
import pathlib
import sys

from mcmc_graph_solver.core import GraphSolver
import mcmc_graph_solver.core as core

edges = json.loads(sys.argv[1])
expected = json.loads(sys.argv[2])
solver = GraphSolver(edges)
assert solver.nodes == expected, (solver.nodes, expected)
assert set(solver.solve()) == set(expected)
assert importlib.metadata.version("mcmc_graph_solver") == "1.0"
actual_core = pathlib.Path(inspect.getfile(core)).resolve()
expected_core = pathlib.Path("/app/mcmc_graph_solver/mcmc_graph_solver/core.py").resolve()
assert actual_core == expected_core, (actual_core, expected_core)
'''

    for seed in ("1", "17", "101", "987654"):
        env = os.environ.copy()
        env.pop("PYTHONPATH", None)
        env["PYTHONHASHSEED"] = seed
        result = subprocess.run(
            [sys.executable, "-c", check_code, json.dumps(edges), json.dumps(expected)],
            cwd="/tmp",
            env=env,
            capture_output=True,
            text=True,
            timeout=20,
        )
        assert result.returncode == 0, (
            f"Installed GraphSolver failed deterministic-node validation with hash seed {seed}.\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )


def test_adversarial_corpus():
    """Retain validation against all supplied corpus files."""
    script_path = "/home/user/graph_filter.py"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."

    clean_dir = "/app/corpora/clean"
    evil_dir = "/app/corpora/evil"

    clean_files = glob.glob(os.path.join(clean_dir, "*.json"))
    evil_files = glob.glob(os.path.join(evil_dir, "*.json"))

    assert len(clean_files) > 0, f"No clean corpus files found in {clean_dir}."
    assert len(evil_files) > 0, f"No evil corpus files found in {evil_dir}."

    clean_failures = []
    for f in clean_files:
        res = subprocess.run(["python3", script_path, f], capture_output=True)
        if res.returncode != 0:
            clean_failures.append(os.path.basename(f))

    evil_failures = []
    for f in evil_files:
        res = subprocess.run(["python3", script_path, f], capture_output=True)
        if res.returncode != 1:
            evil_failures.append(os.path.basename(f))

    error_messages = []
    if clean_failures:
        error_messages.append(f"{len(clean_failures)} of {len(clean_files)} clean modified (rejected): {', '.join(clean_failures)}")
    if evil_failures:
        error_messages.append(f"{len(evil_failures)} of {len(evil_files)} evil bypassed (accepted): {', '.join(evil_failures)}")

    assert not error_messages, "Adversarial corpus validation failed:\n" + "\n".join(error_messages)


def verifier_is_strongly_connected(graph):
    nodes = set(graph)
    for neighbors in graph.values():
        nodes.update(neighbors)
    if not nodes:
        return False

    adjacency = {node: list(graph.get(node, [])) for node in nodes}
    reverse = {node: [] for node in nodes}
    for source, neighbors in adjacency.items():
        for target in neighbors:
            reverse[target].append(source)

    def reachable(start, links):
        seen = {start}
        stack = [start]
        while stack:
            current = stack.pop()
            for target in links[current]:
                if target not in seen:
                    seen.add(target)
                    stack.append(target)
        return seen

    start = next(iter(nodes))
    return reachable(start, adjacency) == nodes and reachable(start, reverse) == nodes


def test_graph_filter_on_generated_graphs_and_argument_count(tmp_path):
    """Exercise graph analysis on fresh paths and labels unknown before verification."""
    script_path = "/home/user/graph_filter.py"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."

    nonce = secrets.token_hex(10)

    def labels(prefix, count):
        return [f"{prefix}_{nonce}_{secrets.token_hex(3)}_{i}" for i in range(count)]

    generated = []

    # Strongly connected rings with extra edges.
    for size in (4, 7, 11):
        ns = labels("vertex", size)
        graph = {
            ns[i]: [ns[(i + 1) % size], ns[(i + 3) % size]]
            for i in range(size)
        }
        generated.append(graph)

    # Two disconnected strongly connected components.
    ns = labels("component", 8)
    generated.append({
        ns[i]: [ns[(i + 1) % 4]] if i < 4 else [ns[4 + ((i - 4 + 1) % 4)]]
        for i in range(8)
    })

    # A path ending in an absorbing/dead state.
    ns = labels("path", 6)
    generated.append({ns[i]: [ns[i + 1]] for i in range(5)} | {ns[5]: []})

    # A one-way connection between two cycles, with no route back.
    ns = labels("trap", 7)
    graph = {
        ns[0]: [ns[1]], ns[1]: [ns[2]], ns[2]: [ns[0], ns[3]],
        ns[3]: [ns[4]], ns[4]: [ns[5]], ns[5]: [ns[6]], ns[6]: [ns[3]],
    }
    generated.append(graph)

    # A referenced node missing from the adjacency dictionary has no outgoing edges.
    ns = labels("missing", 5)
    generated.append({ns[0]: [ns[1]], ns[1]: [ns[2]], ns[2]: [ns[3]], ns[3]: [ns[4]]})

    expected_codes = [0 if verifier_is_strongly_connected(g) else 1 for g in generated]
    assert 0 in expected_codes and 1 in expected_codes

    files = []
    order = list(range(len(generated)))
    random.SystemRandom().shuffle(order)
    for index in order:
        path = tmp_path / f"case_{secrets.token_hex(12)}.json"
        with path.open("w", encoding="utf-8") as handle:
            json.dump(generated[index], handle)
        files.append((path, expected_codes[index]))

    for path, expected_code in files:
        result = subprocess.run(
            [sys.executable, script_path, str(path)],
            capture_output=True,
            text=True,
            timeout=8,
        )
        assert result.returncode == expected_code, (
            f"graph_filter.py returned {result.returncode}, expected {expected_code}, "
            f"for generated graph {path.name}.\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )

    no_argument = subprocess.run(
        [sys.executable, script_path], capture_output=True, text=True, timeout=8
    )
    assert no_argument.returncode != 0, "graph_filter.py must reject invocation with no graph argument"

    two_arguments = subprocess.run(
        [sys.executable, script_path, str(files[0][0]), str(files[1][0])],
        capture_output=True,
        text=True,
        timeout=8,
    )
    assert two_arguments.returncode != 0, "graph_filter.py must reject invocation with more than one argument"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
