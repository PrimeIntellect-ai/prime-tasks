#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import inspect
import json
import os
import random
import re
import secrets
import sqlite3
import subprocess
from collections import Counter, defaultdict, deque

import pytest


SCRIPT_PATH = "/home/user/validate_backup.py"
DB_PATH = "/home/user/backups.db"
VENDORED_ROOT = os.path.realpath("/app/networkx-2.8.8")


def run_validator(path):
    return subprocess.run(
        ["python3", SCRIPT_PATH, path],
        capture_output=True,
        text=True,
        timeout=20,
    )


def read_db_edges():
    assert os.path.isfile(DB_PATH), f"Database {DB_PATH} was not created."
    conn = sqlite3.connect(DB_PATH)
    try:
        cursor = conn.cursor()
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='edges'")
        assert cursor.fetchone() is not None, "Table 'edges' does not exist in the database."
        cursor.execute("SELECT source, target FROM edges")
        return cursor.fetchall()
    finally:
        conn.close()


def independently_is_dag(edges):
    nodes = set()
    outgoing = defaultdict(list)
    indegree = defaultdict(int)
    for edge in edges:
        source = str(edge["source"])
        target = str(edge["target"])
        nodes.add(source)
        nodes.add(target)
        outgoing[source].append(target)
        indegree[target] += 1
        indegree[source] += 0

    queue = deque(node for node in nodes if indegree[node] == 0)
    visited = 0
    while queue:
        node = queue.popleft()
        visited += 1
        for target in outgoing[node]:
            indegree[target] -= 1
            if indegree[target] == 0:
                queue.append(target)
    return visited == len(nodes)


def test_networkx_fixed():
    """Test that the vendored networkx is repaired and is the imported installation."""
    digraph_path = "/app/networkx-2.8.8/networkx/classes/digraph.py"
    assert os.path.isfile(digraph_path), "Vendored digraph.py is missing."

    with open(digraph_path, "r", encoding="utf-8") as source_file:
        source = source_file.read()
    assert re.search(r"def\s+add_node\s*\(self,\s*node_for_adding,\s*\*\*attr\s*\)\s*:", source), \
        "The add_node method signature in vendored digraph.py was not repaired."

    compile_result = subprocess.run(
        ["python3", "-m", "py_compile", digraph_path],
        capture_output=True,
        text=True,
    )
    assert compile_result.returncode == 0, compile_result.stderr

    cmd = [
        "python3",
        "-c",
        "import json, os, networkx as nx; "
        "g = nx.DiGraph(); g.add_node(1); "
        "print(g.nodes()); "
        "print(json.dumps({'path': os.path.realpath(nx.__file__), 'version': nx.__version__}))",
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    assert result.returncode == 0, f"Failed to import or use networkx. Error: {result.stderr}"
    assert "[1]" in result.stdout, "networkx did not behave as expected after fix."

    metadata = json.loads(result.stdout.strip().splitlines()[-1])
    imported_path = os.path.realpath(metadata["path"])
    assert os.path.commonpath([imported_path, VENDORED_ROOT]) == VENDORED_ROOT, \
        f"Imported networkx is not the vendored installation: {imported_path}"
    assert metadata["version"] == "2.8.8", f"Expected networkx 2.8.8, got {metadata['version']}"

    show_result = subprocess.run(
        ["python3", "-m", "pip", "show", "networkx"],
        capture_output=True,
        text=True,
    )
    assert show_result.returncode == 0, "pip does not report networkx as installed."

    import networkx as nx
    assert os.path.commonpath([os.path.realpath(nx.__file__), VENDORED_ROOT]) == VENDORED_ROOT
    assert str(inspect.signature(nx.DiGraph.add_node)) == "(self, node_for_adding, **attr)"


def test_adversarial_corpus():
    """Retain the original checks against the setup corpus."""
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} not found."

    evil_dir = "/home/user/corpus/evil"
    clean_dir = "/home/user/corpus/clean"
    evil_files = glob.glob(os.path.join(evil_dir, "*.json"))
    clean_files = glob.glob(os.path.join(clean_dir, "*.json"))

    assert len(evil_files) > 0, "No evil corpus files found."
    assert len(clean_files) > 0, "No clean corpus files found."

    if os.path.exists(DB_PATH):
        os.remove(DB_PATH)

    evil_bypassed = []
    for path in evil_files:
        result = run_validator(path)
        if result.returncode != 1 or "REJECTED" not in result.stdout:
            evil_bypassed.append(os.path.basename(path))

    clean_failed = []
    for path in clean_files:
        result = run_validator(path)
        if result.returncode != 0 or "ACCEPTED" not in result.stdout:
            clean_failed.append(os.path.basename(path))

    errors = []
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_failed:
        errors.append(f"{len(clean_failed)} of {len(clean_files)} clean modified (failed to accept): {', '.join(clean_failed)}")
    if errors:
        pytest.fail("; ".join(errors))

    db_edges = read_db_edges()
    expected_edges = []
    for path in clean_files:
        with open(path, "r", encoding="utf-8") as json_file:
            for edge in json.load(json_file):
                expected_edges.append((str(edge["source"]), str(edge["target"])))

    assert len(db_edges) == len(expected_edges), \
        f"Expected {len(expected_edges)} edges in DB, found {len(db_edges)}."
    assert Counter(db_edges) == Counter(expected_edges), \
        "Edges in database do not match the expected clean edges."


def test_fresh_randomized_graphs_and_exports(tmp_path):
    """Exercise unpredictable graph contents and verify exports after every invocation."""
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} not found."
    if os.path.exists(DB_PATH):
        os.remove(DB_PATH)

    rng = random.SystemRandom()
    cases = []

    # Random DAGs: edges always follow a secret random topological ordering.
    for _ in range(7):
        count = rng.randint(4, 9)
        nodes = [f"n_{secrets.token_hex(8)}" for _ in range(count)]
        rng.shuffle(nodes)
        edges = [{"source": nodes[i], "target": nodes[i + 1]} for i in range(count - 1)]
        for i in range(count):
            for j in range(i + 2, count):
                if rng.random() < 0.3:
                    edges.append({"source": nodes[i], "target": nodes[j]})
        rng.shuffle(edges)
        cases.append(edges)

    # Random cyclic graphs, including both longer cycles and a self-loop.
    for _ in range(6):
        count = rng.randint(3, 8)
        nodes = [f"n_{secrets.token_hex(8)}" for _ in range(count)]
        edges = [
            {"source": nodes[i], "target": nodes[(i + 1) % count]}
            for i in range(count)
        ]
        if count > 3:
            edges.append({"source": nodes[0], "target": nodes[2]})
        rng.shuffle(edges)
        cases.append(edges)

    loop_node = f"n_{secrets.token_hex(8)}"
    cases.append([{"source": loop_node, "target": loop_node}])
    rng.shuffle(cases)

    expected_exported = []
    for edges in cases:
        path = tmp_path / f"{secrets.token_hex(16)}.json"
        path.write_text(json.dumps(edges), encoding="utf-8")
        expected_dag = independently_is_dag(edges)
        result = run_validator(str(path))

        if expected_dag:
            assert result.returncode == 0, \
                f"A generated DAG was not accepted. stdout={result.stdout!r}, stderr={result.stderr!r}"
            assert "ACCEPTED" in result.stdout, "A generated DAG did not print ACCEPTED."
            expected_exported.extend((str(e["source"]), str(e["target"])) for e in edges)
            actual = read_db_edges()
            assert Counter(actual) == Counter(expected_exported), \
                "Accepted edges were not appended to SQLite exactly as supplied."
        else:
            before = Counter(read_db_edges()) if expected_exported else Counter()
            assert result.returncode == 1, \
                f"A generated cyclic graph was not rejected. stdout={result.stdout!r}, stderr={result.stderr!r}"
            assert "REJECTED" in result.stdout, "A generated cyclic graph did not print REJECTED."
            if os.path.exists(DB_PATH):
                after = Counter(read_db_edges())
                assert after == before, "A rejected graph modified the SQLite export."

    assert expected_exported, "Randomized test unexpectedly generated no accepted edges."
    final_edges = read_db_edges()
    assert len(final_edges) == len(expected_exported)
    assert Counter(final_edges) == Counter(expected_exported)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
