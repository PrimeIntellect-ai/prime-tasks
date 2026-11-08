#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import heapq
import json
import os
import secrets
import subprocess
import pytest

OUTPUT_JSON = "/home/user/output.json"
GRAPH_ANALYZER_DIR = "/home/user/graph_analyzer"
CARGO_TOML = os.path.join(GRAPH_ANALYZER_DIR, "Cargo.toml")
NODES_CSV = "/home/user/data/nodes.csv"
EDGES_CSV = "/home/user/data/edges.csv"


def test_rust_project_exists():
    assert os.path.isdir(GRAPH_ANALYZER_DIR), f"Rust project directory {GRAPH_ANALYZER_DIR} is missing."
    assert os.path.isfile(CARGO_TOML), f"Cargo.toml is missing in {GRAPH_ANALYZER_DIR}."


def test_output_json_exists():
    assert os.path.isfile(OUTPUT_JSON), f"Output file {OUTPUT_JSON} was not created."


def test_output_json_content():
    assert os.path.isfile(OUTPUT_JSON), f"Output file {OUTPUT_JSON} is missing."

    with open(OUTPUT_JSON, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {OUTPUT_JSON} does not contain valid JSON.")

    expected_data = [
        {"id": "N5", "name": "StationE", "cost": 20},
        {"id": "N4", "name": "StationD", "cost": 10}
    ]

    assert isinstance(data, list), f"Expected a JSON array, but got {type(data).__name__}."
    assert len(data) == len(expected_data), f"Expected {len(expected_data)} items, but got {len(data)}."

    for i, (actual, expected) in enumerate(zip(data, expected_data)):
        assert actual.get("id") == expected["id"], f"Item at index {i} has incorrect id. Expected {expected['id']}, got {actual.get('id')}."
        assert actual.get("name") == expected["name"], f"Item at index {i} has incorrect name. Expected {expected['name']}, got {actual.get('name')}."
        assert actual.get("cost") == expected["cost"], f"Item at index {i} has incorrect cost. Expected {expected['cost']}, got {actual.get('cost')}."


def test_output_json_format():
    assert os.path.isfile(OUTPUT_JSON), f"Output file {OUTPUT_JSON} is missing."

    with open(OUTPUT_JSON, "r") as f:
        content = f.read()

    content_stripped = content.strip()
    assert "\n" not in content_stripped, "Output JSON should be a single line, not pretty-printed."


def compute_expected(nodes, edges):
    by_id = {node["id"]: node for node in nodes}
    adjacency = {node_id: [] for node_id in by_id}
    for edge in edges:
        adjacency.setdefault(edge["src"], []).append((edge["dst"], int(edge["cost"])))

    distances = {"N1": 0}
    queue = [(0, "N1")]
    while queue:
        distance, node_id = heapq.heappop(queue)
        if distance != distances.get(node_id):
            continue
        for destination, cost in adjacency.get(node_id, []):
            candidate = distance + cost
            if candidate < distances.get(destination, 10**30):
                distances[destination] = candidate
                heapq.heappush(queue, (candidate, destination))

    results = []
    for node_id, distance in distances.items():
        if node_id == "N1" or distance > 35:
            continue
        node = by_id[node_id]
        if node["type"] == "Maintenance":
            continue
        results.append({"id": node_id, "name": node["name"], "cost": distance})
    results.sort(key=lambda item: item["name"], reverse=True)
    return results[2:4]


def write_fixture(nodes, edges):
    with open(NODES_CSV, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=["id", "name", "type"], lineterminator="\n")
        writer.writeheader()
        writer.writerows(nodes)
    with open(EDGES_CSV, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=["src", "dst", "cost"], lineterminator="\n")
        writer.writeheader()
        writer.writerows(edges)


def run_submission(expected):
    flag_args = [
        "--start", "N1", "--max-cost", "35", "--exclude-type", "Maintenance",
        "--page-size", "2", "--page-number", "2", "--output", OUTPUT_JSON
    ]
    underscore_args = [
        "--start", "N1", "--max_cost", "35", "--exclude_type", "Maintenance",
        "--page_size", "2", "--page_number", "2", "--output", OUTPUT_JSON
    ]
    candidates = [
        [],
        ["N1", "35", "Maintenance", "2", "2"],
        ["N1", "35", "Maintenance", "2", "2", OUTPUT_JSON],
        flag_args,
        underscore_args,
        ["--nodes", NODES_CSV, "--edges", EDGES_CSV] + flag_args,
        ["--nodes-file", NODES_CSV, "--edges-file", EDGES_CSV] + flag_args,
    ]

    env = os.environ.copy()
    env.update({
        "NODES_CSV": NODES_CSV,
        "EDGES_CSV": EDGES_CSV,
        "START_NODE": "N1",
        "MAX_COST": "35",
        "EXCLUDE_TYPE": "Maintenance",
        "PAGE_SIZE": "2",
        "PAGE_NUMBER": "2",
        "OUTPUT_JSON": OUTPUT_JSON,
    })

    diagnostics = []
    for args in candidates:
        try:
            os.remove(OUTPUT_JSON)
        except FileNotFoundError:
            pass
        try:
            completed = subprocess.run(
                ["cargo", "run", "--quiet", "--"] + args,
                cwd=GRAPH_ANALYZER_DIR,
                env=env,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=120,
            )
        except subprocess.TimeoutExpired:
            diagnostics.append(f"arguments {args!r}: timed out")
            continue

        if completed.returncode != 0:
            diagnostics.append(f"arguments {args!r}: exit {completed.returncode}: {completed.stderr[-500:]}")
            continue
        if not os.path.isfile(OUTPUT_JSON):
            diagnostics.append(f"arguments {args!r}: output.json was not created")
            continue
        try:
            with open(OUTPUT_JSON, "r") as f:
                content = f.read()
            actual = json.loads(content)
        except (OSError, json.JSONDecodeError) as exc:
            diagnostics.append(f"arguments {args!r}: invalid output: {exc}")
            continue

        if actual == expected and "\n" not in content.strip():
            return
        diagnostics.append(f"arguments {args!r}: expected {expected!r}, got {actual!r}")

    pytest.fail("The Rust program did not produce the derived result for changed CSV input. " + " | ".join(diagnostics))


def test_program_executes_and_queries_changed_csv_data():
    with open(NODES_CSV, "rb") as f:
        original_nodes = f.read()
    with open(EDGES_CSV, "rb") as f:
        original_edges = f.read()
    original_output = None
    if os.path.isfile(OUTPUT_JSON):
        with open(OUTPUT_JSON, "rb") as f:
            original_output = f.read()

    try:
        for _ in range(2):
            names = {f"N{i}": "Station_" + secrets.token_hex(6) for i in range(1, 11)}
            nodes = [
                {"id": f"N{i}", "name": names[f"N{i}"],
                 "type": "Maintenance" if i in (3, 8) else ("Hub" if i == 1 else "Normal")}
                for i in range(1, 11)
            ]
            edges = []
            for i in range(2, 10):
                edges.append({"src": "N1", "dst": f"N{i}", "cost": str(8 + secrets.randbelow(25))})
            edges.extend([
                {"src": "N1", "dst": "N3", "cost": "3"},
                {"src": "N3", "dst": "N4", "cost": "4"},
                {"src": "N3", "dst": "N6", "cost": "7"},
                {"src": "N4", "dst": "N5", "cost": "5"},
                {"src": "N6", "dst": "N9", "cost": "6"},
                {"src": "N9", "dst": "N10", "cost": "4"},
                {"src": "N10", "dst": "N2", "cost": "50"},
            ])
            write_fixture(nodes, edges)
            run_submission(compute_expected(nodes, edges))
    finally:
        with open(NODES_CSV, "wb") as f:
            f.write(original_nodes)
        with open(EDGES_CSV, "wb") as f:
            f.write(original_edges)
        if original_output is None:
            try:
                os.remove(OUTPUT_JSON)
            except FileNotFoundError:
                pass
        else:
            with open(OUTPUT_JSON, "wb") as f:
                f.write(original_output)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
