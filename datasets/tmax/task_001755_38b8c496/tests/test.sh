#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import subprocess
import tempfile


def expected_output(edges, queries):
    adj = {}
    for source, target in edges:
        adj.setdefault(source, []).append(target)

    output = []
    for query in queries:
        results = set()
        for first_hop in adj.get(query, []):
            results.add(first_hop)
            for second_hop in adj.get(first_hop, []):
                results.add(second_hop)
        output.append(",".join(sorted(results)))
    return output


def run_engine(executable, graph_path, queries):
    proc = subprocess.run(
        [executable, graph_path],
        input="\n".join(queries) + "\n",
        text=True,
        capture_output=True,
        timeout=5,
    )
    assert proc.returncode == 0, f"Graph query engine failed: {proc.stderr}"
    lines = proc.stdout.splitlines()
    assert len(lines) == len(queries), (
        f"Expected {len(queries)} output lines, got {len(lines)}. "
        f"stdout={proc.stdout!r}, stderr={proc.stderr!r}"
    )
    return lines


def test_graph_extraction():
    graph_path = "/home/user/graph.txt"
    assert os.path.isfile(graph_path), f"Graph edge list not found at {graph_path}"

    with open(graph_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_edges = {
        "Alpha,Beta",
        "Beta,Gamma",
        "Alpha,Delta",
        "Gamma,Epsilon",
        "Delta,Zeta",
    }
    actual_edges = set(lines)
    assert actual_edges == expected_edges, f"Graph edges do not match expected. Got: {actual_edges}"


def test_graph_query_engine():
    agent_exec = "/home/user/graph_query"
    source_path = "/home/user/graph_tool.go"
    graph_path = "/home/user/graph.txt"

    assert os.path.isfile(agent_exec), f"Agent executable not found at {agent_exec}"
    assert os.access(agent_exec, os.X_OK), f"Agent executable {agent_exec} is not executable"
    assert os.path.isfile(source_path), f"Go source not found at {source_path}"

    built_exec = os.path.join(tempfile.mkdtemp(prefix="graph-build-"), "graph_query")
    build = subprocess.run(
        ["go", "build", "-o", built_exec, source_path],
        text=True,
        capture_output=True,
        timeout=30,
    )
    assert build.returncode == 0, f"graph_tool.go does not build: {build.stderr}"

    fixed_edges = [
        ("Alpha", "Beta"),
        ("Beta", "Gamma"),
        ("Alpha", "Delta"),
        ("Gamma", "Epsilon"),
        ("Delta", "Zeta"),
    ]
    fixed_queries = ["Alpha", "Beta", "Gamma", "Delta", "Epsilon", "Zeta", "Omega"]
    fixed_expected = expected_output(fixed_edges, fixed_queries)

    for executable in (agent_exec, built_exec):
        assert run_engine(executable, graph_path, fixed_queries) == fixed_expected

    # Exercise the implementation on an unpredictable graph so behavior cannot be
    # hardcoded for the seven nodes in the audio memo.
    rng = random.SystemRandom()
    nodes = [f"N_{secrets.token_hex(5)}" for _ in range(16)]
    edges = [(nodes[i], nodes[i + 1]) for i in range(len(nodes) - 1)]
    for source in nodes:
        for target in nodes:
            if source != target and rng.random() < 0.18:
                edges.append((source, target))
    edges = list(dict.fromkeys(edges))
    rng.shuffle(edges)

    unknown = f"Unknown_{secrets.token_hex(6)}"
    queries = nodes + [unknown]
    rng.shuffle(queries)
    queries += [rng.choice(nodes) for _ in range(20)]
    dynamic_expected = expected_output(edges, queries)

    fd, dynamic_graph = tempfile.mkstemp(prefix="graph-", suffix=".txt")
    with os.fdopen(fd, "w") as graph_file:
        for source, target in edges:
            graph_file.write(f"{source},{target}\n")

    for executable in (agent_exec, built_exec):
        actual = run_engine(executable, dynamic_graph, queries)
        assert actual == dynamic_expected, (
            f"Incorrect 1-or-2-hop results for generated graph using {executable}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
