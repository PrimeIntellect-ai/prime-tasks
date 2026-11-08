#!/bin/bash
set -e
mkdir -p /logs/verifier
export PATH="/opt/rust/bin:$PATH"
export RUSTUP_HOME=/opt/rust
export CARGO_HOME=/opt/rust

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import secrets
import subprocess

import pytest

OUTPUT_JSON_PATH = "/home/user/output.json"
RUST_PROJECT_DIR = "/home/user/graph_pipeline"
NODES_CSV_PATH = "/home/user/data/nodes.csv"
EDGES_CSV_PATH = "/home/user/data/edges.csv"

ORIGINAL_NODES = """id,type
N001,Account
N002,Account
N003,Account
N004,Account
N005,Account
N006,Account
N007,Account
"""

ORIGINAL_EDGES = """source,target,timestamp,weight
N001,N002,100,50
N001,N002,200,-10
N001,N003,150,20
N001,N003,50,10
N003,N004,300,5
N003,N005,400,15
N003,N005,450,-5
N004,N006,500,10
N002,N007,600,20
"""


def write_fixture(nodes_text, edges_text):
    with open(NODES_CSV_PATH, "w", newline="") as f:
        f.write(nodes_text)
    with open(EDGES_CSV_PATH, "w", newline="") as f:
        f.write(edges_text)


def run_pipeline(timeout=300):
    env = os.environ.copy()
    env["PATH"] = "/opt/rust/bin:" + env.get("PATH", "")
    env["RUSTUP_HOME"] = "/opt/rust"
    env["CARGO_HOME"] = "/opt/rust"
    result = subprocess.run(
        ["cargo", "run", "--quiet", "--manifest-path", os.path.join(RUST_PROJECT_DIR, "Cargo.toml")],
        cwd=RUST_PROJECT_DIR,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
    )
    assert result.returncode == 0, (
        "Rust pipeline failed to compile or run.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def load_output():
    assert os.path.isfile(OUTPUT_JSON_PATH), f"Output file {OUTPUT_JSON_PATH} does not exist."
    with open(OUTPUT_JSON_PATH, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {OUTPUT_JSON_PATH} is not valid JSON.")


def derive_expected(edges):
    newest = {}
    for source, target, timestamp, weight in edges:
        key = (source, target)
        if key not in newest or timestamp > newest[key][0]:
            newest[key] = (timestamp, weight)

    adjacency = {}
    for (source, target), (_, weight) in newest.items():
        if weight >= 0:
            adjacency.setdefault(source, set()).add(target)

    frontier = {"N001"}
    reachable = set()
    for _ in range(2):
        next_frontier = set()
        for source in frontier:
            next_frontier.update(adjacency.get(source, set()))
        reachable.update(next_frontier)
        frontier = next_frontier
    return sorted(reachable)


def test_rust_project_exists():
    """Verify that the Rust project directory exists."""
    assert os.path.isdir(RUST_PROJECT_DIR), f"Rust project directory {RUST_PROJECT_DIR} does not exist."
    cargo_toml = os.path.join(RUST_PROJECT_DIR, "Cargo.toml")
    assert os.path.isfile(cargo_toml), f"Cargo.toml not found in {RUST_PROJECT_DIR}."
    src_dir = os.path.join(RUST_PROJECT_DIR, "src")
    assert os.path.isdir(src_dir), f"src directory not found in {RUST_PROJECT_DIR}."


def test_output_json_exists():
    """Compile and run the Rust project, then verify that its output was created."""
    write_fixture(ORIGINAL_NODES, ORIGINAL_EDGES)
    run_pipeline()
    assert os.path.isfile(OUTPUT_JSON_PATH), f"Output file {OUTPUT_JSON_PATH} does not exist."


def test_output_json_content():
    """Verify the contents produced by the Rust program for the original data."""
    write_fixture(ORIGINAL_NODES, ORIGINAL_EDGES)
    run_pipeline(timeout=120)
    data = load_output()

    assert "reachable_nodes" in data, "JSON output is missing the 'reachable_nodes' key."
    reachable = data["reachable_nodes"]
    assert isinstance(reachable, list), "'reachable_nodes' must be a list."

    expected = ["N003", "N004"]
    assert reachable == expected, f"Expected reachable_nodes to be {expected}, but got {reachable}."


def test_pipeline_behavior_on_unseen_csv_data():
    """Exercise ingestion, latest-edge cleaning, deletion handling, and two-hop traversal."""
    token = secrets.token_hex(6).upper()
    ids = {name: f"N{name}_{token}" for name in "ABCDEFGHXYZ"}

    node_ids = ["N001"] + list(ids.values())
    nodes_text = "id,type\n" + "".join(f"{node},Account\n" for node in node_ids)

    edges = [
        ("N001", ids["A"], 110, 9),
        ("N001", ids["A"], 910, -1),       # latest row deletes this edge
        ("N001", ids["B"], 120, -8),
        ("N001", ids["B"], 920, 4),        # latest row restores this edge
        ("N001", ids["C"], 300, 6),
        ("N001", ids["H"], 350, 0),        # zero is not a deletion
        (ids["B"], ids["D"], 400, 3),
        (ids["C"], ids["D"], 410, 7),       # duplicate reachability must be unique
        (ids["C"], ids["E"], 420, 8),
        (ids["C"], ids["E"], 930, -2),      # deleted second-hop edge
        (ids["B"], "N001", 500, 1),        # a two-hop cycle includes N001
        (ids["H"], ids["G"], 510, 2),
        (ids["D"], ids["F"], 600, 5),       # three hops, so it must be excluded
        (ids["X"], ids["Y"], 700, 5),       # disconnected component
        (ids["Z"], "N001", 800, 5),        # wrong direction for reachability
    ]

    # Vary row order so the implementation cannot rely on CSV ordering.
    order = [8, 0, 12, 3, 14, 6, 1, 10, 5, 13, 2, 11, 7, 4, 9]
    ordered_edges = [edges[i] for i in order]
    edges_text = "source,target,timestamp,weight\n" + "".join(
        f"{source},{target},{timestamp},{weight}\n"
        for source, target, timestamp, weight in ordered_edges
    )
    expected = derive_expected(ordered_edges)

    try:
        write_fixture(nodes_text, edges_text)
        run_pipeline(timeout=120)
        data = load_output()
        assert "reachable_nodes" in data, "JSON output is missing the 'reachable_nodes' key."
        reachable = data["reachable_nodes"]
        assert isinstance(reachable, list), "'reachable_nodes' must be a list."
        assert reachable == expected, f"Expected reachable_nodes to be {expected}, but got {reachable}."
    finally:
        write_fixture(ORIGINAL_NODES, ORIGINAL_EDGES)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
