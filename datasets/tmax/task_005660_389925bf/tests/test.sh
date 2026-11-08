#!/bin/bash
set -e
mkdir -p /logs/verifier

cp -a /home/user/dataset.db /tmp/original_dataset.db
if [ -f /home/user/deadlocks.json ]; then
    cp -a /home/user/deadlocks.json /tmp/original_deadlocks.json
    HAD_OUTPUT=1
else
    HAD_OUTPUT=0
fi

restore_files() {
    rm -f /home/user/dataset.db /home/user/dataset.db-wal /home/user/dataset.db-shm
    cp -a /tmp/original_dataset.db /home/user/dataset.db
    if [ "$HAD_OUTPUT" = "1" ]; then
        cp -a /tmp/original_deadlocks.json /home/user/deadlocks.json
    else
        rm -f /home/user/deadlocks.json
    fi
}
trap restore_files EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import sqlite3
import subprocess
import pytest

GO_FILE = "/home/user/find_deadlocks.go"
DB_FILE = "/home/user/dataset.db"
JSON_FILE = "/home/user/deadlocks.json"
BINARY = "/tmp/find_deadlocks_submission"


def run_program():
    if os.path.exists(JSON_FILE):
        os.remove(JSON_FILE)
    result = subprocess.run(
        [BINARY],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"Go program exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(JSON_FILE), f"Program did not create {JSON_FILE}."


def replace_database(edges):
    for path in (DB_FILE, DB_FILE + "-wal", DB_FILE + "-shm"):
        if os.path.exists(path):
            os.remove(path)
    connection = sqlite3.connect(DB_FILE)
    try:
        connection.execute("CREATE TABLE wait_graph (waiting_tx TEXT, blocking_tx TEXT)")
        connection.executemany("INSERT INTO wait_graph VALUES (?, ?)", edges)
        connection.commit()
    finally:
        connection.close()


def expected_cycles(edges):
    adjacency = {}
    nodes = set()
    for waiting, blocking in edges:
        nodes.add(waiting)
        nodes.add(blocking)
        adjacency.setdefault(waiting, set()).add(blocking)

    cycles = set()

    def canonical(path):
        rotations = [tuple(path[i:] + path[:i]) for i in range(len(path))]
        return min(rotations)

    def search(start, current, path, visited):
        for next_node in adjacency.get(current, set()):
            if next_node == start:
                cycles.add(canonical(path))
            elif next_node not in visited:
                search(start, next_node, path + [next_node], visited | {next_node})

    for start in sorted(nodes):
        search(start, start, [start], {start})

    return [list(cycle) for cycle in sorted(cycles)]


def load_strict_output():
    with open(JSON_FILE, "r") as handle:
        data = json.load(handle)
    assert isinstance(data, dict), "Top-level JSON value must be an object."
    assert set(data.keys()) == {"deadlocks"}, "JSON must contain exactly the 'deadlocks' key."
    assert isinstance(data["deadlocks"], list), "'deadlocks' should be a list."
    return data


def test_go_file_exists():
    go_file = "/home/user/find_deadlocks.go"
    assert os.path.isfile(go_file), f"Go source file {go_file} does not exist."


def test_program_executes_on_original_database():
    build = subprocess.run(
        ["go", "build", "-o", BINARY, "find_deadlocks.go"],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    assert build.returncode == 0, (
        f"Could not build find_deadlocks.go.\nstdout:\n{build.stdout}\nstderr:\n{build.stderr}"
    )
    run_program()


def test_json_output_exists():
    json_file = "/home/user/deadlocks.json"
    assert os.path.isfile(json_file), f"JSON output file {json_file} does not exist."


def test_json_output_content():
    json_file = "/home/user/deadlocks.json"
    assert os.path.isfile(json_file), f"JSON output file {json_file} does not exist."

    with open(json_file, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {json_file} does not contain valid JSON.")

    assert "deadlocks" in data, "JSON output is missing the 'deadlocks' key."

    deadlocks = data["deadlocks"]
    assert isinstance(deadlocks, list), "'deadlocks' should be a list."

    expected_deadlocks = [
        ["T_A", "T_B", "T_C"],
        ["T_D", "T_E"],
        ["T_W", "T_X", "T_Y", "T_Z"]
    ]

    assert deadlocks == expected_deadlocks, f"Expected deadlocks {expected_deadlocks}, but got {deadlocks}."


def test_modified_graph_with_overlapping_cycles():
    edges = [
        ("Alpha", "Beta"),
        ("Beta", "Gamma"),
        ("Gamma", "Alpha"),
        ("Alpha", "Delta"),
        ("Delta", "Alpha"),
        ("Beta", "Delta"),
        ("Delta", "Epsilon"),
        ("Epsilon", "Beta"),
        ("Loose1", "Loose2"),
    ]
    replace_database(edges)
    run_program()
    assert load_strict_output() == {"deadlocks": expected_cycles(edges)}


def test_deterministically_generated_graphs():
    for seed in (731, 1907):
        rng = random.Random(seed)
        nodes = [f"S{seed}_{letter}" for letter in "ABCDEFG"]
        edge_set = {
            (nodes[0], nodes[1]),
            (nodes[1], nodes[2]),
            (nodes[2], nodes[0]),
            (nodes[3], nodes[4]),
            (nodes[4], nodes[3]),
        }
        for source in nodes:
            for target in nodes:
                if source != target and rng.random() < 0.20:
                    edge_set.add((source, target))
        edges = list(edge_set)
        rng.shuffle(edges)
        replace_database(edges)
        run_program()
        actual = load_strict_output()
        expected = {"deadlocks": expected_cycles(edges)}
        assert actual == expected, f"Incorrect result for generated graph with seed {seed}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
