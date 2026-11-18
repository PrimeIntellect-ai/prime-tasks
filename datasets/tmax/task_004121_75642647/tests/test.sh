#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import random
import secrets
import subprocess
from collections import Counter, defaultdict

import pandas as pd
import pytest

EDGES_FILE = "/home/user/edges.csv"
NODES_FILE = "/home/user/nodes.csv"
SOURCE_FILE = "/home/user/process_graph.cpp"
EXECUTABLE = "/home/user/process_graph"
RESULTS_FILE = "/home/user/final_results.csv"

EXPECTED_EDGES = [
    (1, 2, 10),
    (2, 3, 15),
    (400, 500, 20),
    (500, 600, 30),
    (600, 700, 40),
]


def golden_rows(edges):
    adj = defaultdict(list)
    for u, v, w in edges:
        adj[int(u)].append((int(v), float(w)))

    two_hop = {}
    for u, outgoing in adj.items():
        for v, w1 in outgoing:
            for c, w2 in adj.get(v, []):
                if u != c:
                    total = w1 + w2
                    key = (u, c)
                    if key not in two_hop or total > two_hop[key]:
                        two_hop[key] = total

    rows = [(u, c, weight) for (u, c), weight in two_hop.items()]
    rows.sort(key=lambda row: (-row[2], row[0], row[1]))
    return rows[:15]


def assert_results_match(edges):
    assert os.path.isfile(RESULTS_FILE), f"File {RESULTS_FILE} is missing."
    try:
        actual = pd.read_csv(RESULTS_FILE)
    except Exception as exc:
        pytest.fail(f"Failed to read {RESULTS_FILE}: {exc}")

    assert list(actual.columns) == ["source", "target", "total_weight"], \
        "final_results.csv must have exactly the header source,target,total_weight"

    expected = golden_rows(edges)
    assert len(actual) == len(expected), \
        f"Expected {len(expected)} result rows, got {len(actual)}"

    for i, (u, c, weight) in enumerate(expected):
        row = actual.iloc[i]
        assert int(row["source"]) == u, f"Wrong source at row {i}"
        assert int(row["target"]) == c, f"Wrong target at row {i}"
        assert abs(float(row["total_weight"]) - weight) < 1e-6, \
            f"Wrong total_weight at row {i}"


def write_dataset(nodes, edges):
    with open(NODES_FILE, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["node_id", "label"])
        for i, node in enumerate(nodes):
            writer.writerow([node, f"N{i}"])

    with open(EDGES_FILE, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["source", "target", "weight"])
        writer.writerows(edges)


def run_program():
    try:
        completed = subprocess.run(
            [EXECUTABLE],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("process_graph timed out")
    assert completed.returncode == 0, \
        f"process_graph failed with code {completed.returncode}: {completed.stderr}"


def test_edges_appended():
    """Test that the 3 missing edges were appended and the original input was preserved."""
    assert os.path.isfile(EDGES_FILE), f"File {EDGES_FILE} is missing."
    df = pd.read_csv(EDGES_FILE)

    required_edges = [
        (400, 500, 20),
        (500, 600, 30),
        (600, 700, 40),
    ]
    for u, v, w in required_edges:
        match = df[(df['source'] == u) & (df['target'] == v) & (df['weight'] == w)]
        assert not match.empty, f"Missing required edge in edges.csv: source={u}, target={v}, weight={w}"

    assert list(df.columns) == ["source", "target", "weight"]
    actual_edges = Counter(
        (int(row.source), int(row.target), int(row.weight))
        for row in df.itertuples(index=False)
    )
    assert actual_edges == Counter(EXPECTED_EDGES), \
        "edges.csv must contain exactly the two original edges and the three requested appended edges"


def test_final_results_accuracy():
    """Retain the original final-results assertion against the submitted dataset."""
    assert os.path.isfile(RESULTS_FILE), f"File {RESULTS_FILE} is missing."
    edges_df = pd.read_csv(EDGES_FILE)

    adj = {}
    for _, row in edges_df.iterrows():
        u, v, w = int(row['source']), int(row['target']), float(row['weight'])
        if u not in adj:
            adj[u] = []
        adj[u].append((v, w))

    two_hop = {}
    for u in adj:
        for v, w1 in adj[u]:
            if v in adj:
                for c, w2 in adj[v]:
                    if u != c:
                        total_w = w1 + w2
                        if (u, c) not in two_hop or total_w > two_hop[(u, c)]:
                            two_hop[(u, c)] = total_w

    results = [{'source': u, 'target': c, 'total_weight': w} for (u, c), w in two_hop.items()]
    golden_df = pd.DataFrame(results)
    golden_df = golden_df.sort_values(
        by=['total_weight', 'source', 'target'],
        ascending=[False, True, True]
    ).reset_index(drop=True).head(15)

    try:
        agent_df = pd.read_csv(RESULTS_FILE)
    except Exception as e:
        pytest.fail(f"Failed to read {RESULTS_FILE}: {e}")

    if len(agent_df) != len(golden_df):
        accuracy = 0.0
    else:
        matches = 0
        for i in range(len(golden_df)):
            if (agent_df.iloc[i]['source'] == golden_df.iloc[i]['source'] and
                agent_df.iloc[i]['target'] == golden_df.iloc[i]['target'] and
                abs(agent_df.iloc[i]['total_weight'] - golden_df.iloc[i]['total_weight']) < 1e-6):
                matches += 1
        accuracy = matches / len(golden_df)

    assert accuracy >= 0.99, f"Accuracy {accuracy} is below the 0.99 threshold. Expected {len(golden_df)} exact row matches."


def test_source_compiles_and_generates_canonical_results():
    assert os.path.isfile(SOURCE_FILE), f"File {SOURCE_FILE} is missing."
    assert os.path.isfile(SOURCE_FILE) and not os.path.islink(SOURCE_FILE), \
        "process_graph.cpp must be a regular source file"
    completed = subprocess.run(
        ["g++", "-O3", "-std=c++17", SOURCE_FILE, "-o", EXECUTABLE],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert completed.returncode == 0, f"Compilation failed: {completed.stderr}"
    assert os.path.isfile(EXECUTABLE) and os.access(EXECUTABLE, os.X_OK)

    run_program()
    assert_results_match(EXPECTED_EDGES)


def test_executable_on_unpredictable_graph():
    rng = random.Random(secrets.randbits(128))
    base = rng.randint(10000, 1000000)
    nodes = [base + i * rng.randint(2, 9) for i in range(28)]
    nodes = list(dict.fromkeys(nodes))
    while len(nodes) < 28:
        candidate = rng.randint(10000, 2000000)
        if candidate not in nodes:
            nodes.append(candidate)

    edges = []
    # A long chain guarantees many valid 2-hop results and exercises limit 15.
    for i in range(len(nodes) - 1):
        edges.append((nodes[i], nodes[i + 1], rng.randint(1, 80)))
    # Add branches, cycles, and parallel edges to exercise joins, A != C, and max.
    for _ in range(75):
        u = rng.choice(nodes)
        v = rng.choice(nodes)
        if u != v:
            edges.append((u, v, rng.randint(1, 120)))
    u, v = edges[rng.randrange(len(edges))][:2]
    edges.append((u, v, rng.randint(121, 200)))
    rng.shuffle(edges)

    write_dataset(nodes, edges)
    run_program()
    assert_results_match(edges)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
