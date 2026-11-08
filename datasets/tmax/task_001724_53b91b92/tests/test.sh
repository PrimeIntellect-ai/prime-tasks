#!/bin/bash
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import collections
import csv
import json
import os
import random
import re
import shutil
import sqlite3
import subprocess
import tempfile
import uuid

import pytest

SOURCE = "/home/user/workspace/pathfinder.go"
WORKSPACE = "/home/user/workspace"
OUTPUT = "/home/user/output/path.json"
DB = "/home/user/data/researchers.db"
EDGES = "/home/user/data/edges.csv"
TOPICS = "/home/user/data/topics.json"
BINARY = "/tmp/pathfinder_submission"


def run_program(source, target):
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    result = subprocess.run(
        [BINARY, "--source", str(source), "--target", str(target)],
        cwd=WORKSPACE,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"Program failed for --source {source} --target {target}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(OUTPUT), f"Output file {OUTPUT} was not created."
    try:
        with open(OUTPUT, "r", encoding="utf-8") as f:
            return json.load(f)
    except json.JSONDecodeError as exc:
        pytest.fail(f"Output file {OUTPUT} does not contain valid JSON: {exc}")


def assert_original_output(data):
    assert "path" in data, "The JSON output must contain a 'path' key."
    path_data = data["path"]
    assert isinstance(path_data, list), "The 'path' key must map to a JSON array."

    expected_path = [
        {"id": 1, "name": "Alice", "topics": ["AI", "Graph"]},
        {"id": 4, "name": "Diana", "topics": ["Data Science", "AI"]},
        {"id": 5, "name": "Eve", "topics": ["Graph", "Bioinformatics"]},
    ]
    assert len(path_data) == len(expected_path), (
        f"Expected path length of {len(expected_path)}, but got {len(path_data)}."
    )
    for i, (actual_node, expected_node) in enumerate(zip(path_data, expected_path)):
        assert "id" in actual_node, f"Node at index {i} is missing the 'id' field."
        assert "name" in actual_node, f"Node at index {i} is missing the 'name' field."
        assert "topics" in actual_node, f"Node at index {i} is missing the 'topics' field."
        assert actual_node["id"] == expected_node["id"], (
            f"Node at index {i} has incorrect 'id'. Expected {expected_node['id']}, got {actual_node['id']}."
        )
        assert actual_node["name"] == expected_node["name"], (
            f"Node at index {i} has incorrect 'name'. Expected {expected_node['name']}, got {actual_node['name']}."
        )
        actual_topics = sorted(actual_node["topics"]) if isinstance(actual_node["topics"], list) else actual_node["topics"]
        expected_topics = sorted(expected_node["topics"])
        assert actual_topics == expected_topics, (
            f"Node at index {i} has incorrect 'topics'. Expected {expected_topics}, got {actual_topics}."
        )


def load_expected_data():
    graph = collections.defaultdict(set)
    with open(EDGES, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == ["source", "target"], "edges.csv header is invalid"
        for row in reader:
            a, b = int(row["source"]), int(row["target"])
            graph[a].add(b)
            graph[b].add(a)

    with sqlite3.connect(DB) as conn:
        names = {row[0]: row[1] for row in conn.execute("SELECT id, name FROM nodes")}
    with open(TOPICS, encoding="utf-8") as f:
        topics = json.load(f)
    return graph, names, topics


def shortest_distance(graph, source, target):
    queue = collections.deque([(source, 0)])
    seen = {source}
    while queue:
        node, distance = queue.popleft()
        if node == target:
            return distance
        for nxt in graph[node]:
            if nxt not in seen:
                seen.add(nxt)
                queue.append((nxt, distance + 1))
    return None


def assert_derived_output(data, source, target):
    assert isinstance(data, dict), "Top-level JSON value must be an object."
    assert set(data) == {"path"}, "Top-level object must contain only the 'path' field."
    path = data["path"]
    assert isinstance(path, list) and path, "The 'path' field must be a non-empty array."

    graph, names, topics = load_expected_data()
    expected_distance = shortest_distance(graph, source, target)
    assert expected_distance is not None, "Verifier test graph unexpectedly has no path."
    assert len(path) - 1 == expected_distance, "Returned path is not a shortest path."

    ids = []
    for index, node in enumerate(path):
        assert isinstance(node, dict), f"Path entry {index} must be an object."
        assert set(node) == {"id", "name", "topics"}, (
            f"Path entry {index} must contain exactly id, name, and topics."
        )
        assert isinstance(node["id"], int) and not isinstance(node["id"], bool)
        assert isinstance(node["name"], str)
        assert isinstance(node["topics"], list)
        assert all(isinstance(topic, str) for topic in node["topics"])
        node_id = node["id"]
        ids.append(node_id)
        assert node_id in names, f"Unknown researcher ID {node_id} in path."
        assert node["name"] == names[node_id], f"Incorrect SQLite name for ID {node_id}."
        assert node["topics"] == topics.get(str(node_id), []), f"Incorrect topics for ID {node_id}."

    assert ids[0] == source and ids[-1] == target, "Path endpoints are incorrect."
    for a, b in zip(ids, ids[1:]):
        assert b in graph[a], f"{a} -> {b} is not an edge in edges.csv."


def test_pathfinder_program():
    assert os.path.isfile(SOURCE), f"Required Go source file {SOURCE} does not exist."
    with open(SOURCE, encoding="utf-8") as f:
        source_text = f.read()

    assert "github.com/mattn/go-sqlite3" in source_text, (
        "The program must use github.com/mattn/go-sqlite3 for SQLite interaction."
    )
    assert re.search(r"(?is)select\s+.+?\s+from\s+nodes\b.+?where\s+.+?(?:\?|[$:@][A-Za-z_][A-Za-z0-9_]*)", source_text), (
        "The nodes lookup SQL must contain a parameter placeholder."
    )
    parameter_call = re.search(r"(?s)\.(?:Query|QueryRow)\s*\([^)]*,[^)]*\)", source_text)
    prepared_call = re.search(r"\.Prepare(?:Context)?\s*\(", source_text) and re.search(
        r"(?s)\.(?:Query|QueryRow|Exec)(?:Context)?\s*\(\s*[^)\s][^)]*\)", source_text
    )
    assert parameter_call or prepared_call, "The SQLite lookup must bind a value to its parameterized query."

    build = subprocess.run(
        ["go", "build", "-o", BINARY, SOURCE],
        cwd=WORKSPACE,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=120,
    )
    assert build.returncode == 0, f"Go program did not compile.\nstdout:\n{build.stdout}\nstderr:\n{build.stderr}"

    # Preserve the original assertion and ensure it is satisfied by executing the program.
    assert_original_output(run_program(1, 5))

    backup_dir = tempfile.mkdtemp(prefix="pathfinder-data-")
    backup_db = os.path.join(backup_dir, "researchers.db")
    backup_edges = os.path.join(backup_dir, "edges.csv")
    backup_topics = os.path.join(backup_dir, "topics.json")
    shutil.copy2(DB, backup_db)
    shutil.copy2(EDGES, backup_edges)
    shutil.copy2(TOPICS, backup_topics)

    base = random.SystemRandom().randint(10000, 50000)
    a, b, c, d, e = [base + offset for offset in range(5)]
    marker = uuid.uuid4().hex
    names = {node_id: f"Researcher-{marker}-{node_id}" for node_id in (a, b, c, d, e)}

    try:
        with sqlite3.connect(DB) as conn:
            conn.executemany(
                "INSERT OR REPLACE INTO nodes(id, name) VALUES (?, ?)",
                list(names.items()),
            )
            conn.commit()

        with open(EDGES, "w", encoding="utf-8", newline="") as f:
            writer = csv.writer(f, lineterminator="\n")
            writer.writerow(["source", "target"])
            writer.writerows([(a, b), (b, c), (c, e), (a, d), (d, e)])

        dynamic_topics = {
            str(a): [f"topic-{marker}-a"],
            str(b): [f"topic-{marker}-b", "shared"],
            str(c): [f"topic-{marker}-c"],
            # d is deliberately absent and must produce [].
            str(e): [f"topic-{marker}-e"],
        }
        with open(TOPICS, "w", encoding="utf-8") as f:
            json.dump(dynamic_topics, f)

        assert_derived_output(run_program(a, e), a, e)
        assert_derived_output(run_program(c, a), c, a)
    finally:
        shutil.copy2(backup_db, DB)
        shutil.copy2(backup_edges, EDGES)
        shutil.copy2(backup_topics, TOPICS)
        shutil.rmtree(backup_dir, ignore_errors=True)

    # Leave the required final invocation's output in place and retain the original exact check.
    assert_original_output(run_program(1, 5))
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
