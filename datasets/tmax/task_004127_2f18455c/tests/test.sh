#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import subprocess
from collections import defaultdict

import pytest

PROJECT = "/home/user/graph_etl"
MAIN_RS = os.path.join(PROJECT, "src", "main.rs")
INPUT = "/home/user/data/transactions.jsonl"
OUTPUT = "/home/user/etl_output.json"


def test_etl_output_exists():
    assert os.path.exists(OUTPUT), f"Output file {OUTPUT} does not exist. Did your script run successfully?"
    assert os.path.isfile(OUTPUT), f"{OUTPUT} is not a file."


def test_etl_output_content():
    assert os.path.exists(OUTPUT), "Output file missing, cannot test content."

    with open(OUTPUT, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{OUTPUT} does not contain valid JSON.")

    expected_keys = {"top_entity", "total_degree", "in_degree", "out_degree"}
    actual_keys = set(data.keys())

    assert actual_keys == expected_keys, f"JSON keys do not match exactly. Expected {expected_keys}, got {actual_keys}"
    assert data["top_entity"] == "U2", f"Expected top_entity to be 'U2', got '{data['top_entity']}'"
    assert data["total_degree"] == 5, f"Expected total_degree to be 5, got {data['total_degree']}"
    assert data["in_degree"] == 4, f"Expected in_degree to be 4, got {data['in_degree']}"
    assert data["out_degree"] == 1, f"Expected out_degree to be 1, got {data['out_degree']}"


def expected_result(records):
    indegree = defaultdict(int)
    outdegree = defaultdict(int)
    entities = set()
    for record in records:
        source = record["source_node"]
        entities.add(source)
        for destination in record["destinations"]:
            entities.add(destination)
            outdegree[source] += 1
            indegree[destination] += 1

    top = min(entities, key=lambda entity: (-(indegree[entity] + outdegree[entity]), entity))
    return {
        "top_entity": top,
        "total_degree": indegree[top] + outdegree[top],
        "in_degree": indegree[top],
        "out_degree": outdegree[top],
    }


def write_fixture(records):
    with open(INPUT, "w") as f:
        for record in records:
            f.write(json.dumps(record) + "\n")


def run_and_check(executable, records):
    write_fixture(records)
    if os.path.lexists(OUTPUT):
        os.remove(OUTPUT)

    completed = subprocess.run(
        [executable], cwd=PROJECT, text=True, capture_output=True, timeout=30
    )
    assert completed.returncode == 0, (
        f"ETL executable failed with exit code {completed.returncode}.\n"
        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )
    assert os.path.isfile(OUTPUT), "Running the Rust executable did not create etl_output.json"

    try:
        with open(OUTPUT, "r") as f:
            actual = json.load(f)
    except json.JSONDecodeError as exc:
        pytest.fail(f"Rust executable produced invalid JSON: {exc}")

    expected = expected_result(records)
    assert set(actual.keys()) == {"top_entity", "total_degree", "in_degree", "out_degree"}
    assert type(actual["top_entity"]) is str
    assert type(actual["total_degree"]) is int
    assert type(actual["in_degree"]) is int
    assert type(actual["out_degree"]) is int
    assert actual == expected, f"For generated transaction data, expected {expected}, got {actual}"


def test_rust_program_compiles_and_processes_unseen_inputs():
    assert os.path.isfile(MAIN_RS), f"Required Rust source file {MAIN_RS} is missing"

    metadata_run = subprocess.run(
        ["cargo", "metadata", "--no-deps", "--format-version", "1"],
        cwd=PROJECT, text=True, capture_output=True, timeout=30
    )
    assert metadata_run.returncode == 0, f"cargo metadata failed:\n{metadata_run.stderr}"
    metadata = json.loads(metadata_run.stdout)

    main_realpath = os.path.realpath(MAIN_RS)
    targets = [
        target
        for package in metadata["packages"]
        for target in package["targets"]
        if "bin" in target["kind"] and os.path.realpath(target["src_path"]) == main_realpath
    ]
    assert targets, "Cargo does not define src/main.rs as a Rust binary target"
    target = targets[0]

    build = subprocess.run(
        ["cargo", "build", "--bin", target["name"]],
        cwd=PROJECT, text=True, capture_output=True, timeout=120
    )
    assert build.returncode == 0, f"Rust project did not compile:\n{build.stdout}\n{build.stderr}"

    executable = os.path.join(metadata["target_directory"], "debug", target["name"])
    assert os.path.isfile(executable), f"Compiled Rust executable was not found at {executable}"
    assert os.access(executable, os.X_OK), f"Compiled artifact {executable} is not executable"

    with open(INPUT, "rb") as f:
        original_input = f.read()
    with open(OUTPUT, "rb") as f:
        original_output = f.read()

    try:
        # First verify that executing the compiled program handles the supplied fixture.
        supplied_records = [json.loads(line) for line in original_input.decode().splitlines() if line.strip()]
        run_and_check(executable, supplied_records)

        # Exercise a graph and entity names generated only at verification time.
        token = secrets.token_hex(8)
        names = [f"entity_{token}_{i}_{secrets.token_hex(3)}" for i in range(9)]
        possible_edges = [(source, destination) for source in names for destination in names if source != destination]
        chosen_edges = []
        while len(chosen_edges) < 20:
            edge = secrets.choice(possible_edges)
            if edge not in chosen_edges:
                chosen_edges.append(edge)

        grouped = defaultdict(list)
        for source, destination in chosen_edges:
            grouped[source].append(destination)
        random_records = [
            {
                "event_id": f"generated-{index}-{secrets.token_hex(4)}",
                "source_node": source,
                "destinations": destinations,
                "amount": index * 17 + 3,
                "ignored_metadata": {"batch": token},
            }
            for index, (source, destinations) in enumerate(grouped.items())
        ]
        run_and_check(executable, random_records)

        # A cycle gives every entity the same degree and checks lexicographic tie-breaking.
        tie_names = [f"{secrets.token_hex(4)}_tie_{i}" for i in range(4)]
        tie_records = [
            {
                "event_id": f"tie-{i}",
                "source_node": tie_names[i],
                "destinations": [tie_names[(i + 1) % len(tie_names)]],
                "amount": 0,
            }
            for i in range(len(tie_names))
        ]
        run_and_check(executable, tie_records)
    finally:
        with open(INPUT, "wb") as f:
            f.write(original_input)
        with open(OUTPUT, "wb") as f:
            f.write(original_output)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
