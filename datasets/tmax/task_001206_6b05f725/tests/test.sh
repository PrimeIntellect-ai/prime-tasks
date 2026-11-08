#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import ctypes
import json
import os
import runpy
import sys

import networkx as nx
import pytest

OUTPUT = "/home/user/analysis_output.json"
SCRIPT = "/home/user/analyze_logistics.py"
NODES = "/home/user/data/nodes.csv"
EDGES = "/home/user/data/edges.csv"


def expected_results():
    graph = nx.DiGraph()
    with open(NODES, newline="") as f:
        for row in csv.DictReader(f):
            graph.add_node(row["node_id"])
    with open(EDGES, newline="") as f:
        for row in csv.DictReader(f):
            graph.add_edge(row["source"], row["target"], travel_time=float(row["travel_time"]))
    return {
        "pagerank": nx.pagerank(graph, alpha=0.85),
        "shortest_paths_from_HUB_001": nx.single_source_dijkstra_path_length(
            graph, "HUB_001", weight="travel_time"
        ),
    }


def test_requested_script_installed_package_and_c_backend(monkeypatch):
    assert os.path.isfile(SCRIPT), f"Required script {SCRIPT} is missing."

    import fast_graph_analytics as fga

    package_file = os.path.realpath(fga.__file__)
    assert not package_file.startswith("/app/fast_graph_analytics-1.2.0/"), (
        "fast_graph_analytics was not installed into the Python environment."
    )
    library_path = os.path.join(os.path.dirname(package_file), "libpagerank.so")
    assert os.path.isfile(library_path), "Installed C backend libpagerank.so is missing."
    try:
        ctypes.CDLL(library_path)
    except OSError as exc:
        pytest.fail(f"Installed C backend cannot be loaded: {exc}")

    called = {"parse": False, "pagerank": False, "shortest": False}
    original_parse = fga.parse_graph
    original_pagerank = fga.compute_pagerank
    original_shortest = fga.compute_shortest_paths

    def checked_parse(nodes_file, edges_file):
        assert os.path.realpath(nodes_file) == os.path.realpath(NODES)
        assert os.path.realpath(edges_file) == os.path.realpath(EDGES)
        called["parse"] = True
        return original_parse(nodes_file, edges_file)

    def checked_pagerank(graph):
        called["pagerank"] = True
        return original_pagerank(graph)

    def checked_shortest(graph, source):
        assert source == "HUB_001"
        called["shortest"] = True
        return original_shortest(graph, source)

    monkeypatch.setattr(fga, "parse_graph", checked_parse)
    monkeypatch.setattr(fga, "compute_pagerank", checked_pagerank)
    monkeypatch.setattr(fga, "compute_shortest_paths", checked_shortest)
    monkeypatch.setattr(sys, "argv", [SCRIPT])
    monkeypatch.chdir("/home/user")

    if os.path.exists(OUTPUT):
        os.unlink(OUTPUT)
    try:
        runpy.run_path(SCRIPT, run_name="__main__")
    except SystemExit as exc:
        assert exc.code in (None, 0), f"Analysis script exited with status {exc.code}."

    assert called["parse"], "The script did not use fast_graph_analytics.parse_graph."
    assert called["pagerank"], "The script did not use the C-backed PageRank function."
    assert called["shortest"], "The script did not use fast_graph_analytics.compute_shortest_paths."


def test_analysis_output_exists():
    assert os.path.isfile(OUTPUT), f"Output file {OUTPUT} is missing."


def test_analysis_output_structure():
    with open(OUTPUT, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Output file {OUTPUT} is not valid JSON.")

    assert "pagerank" in data, "Missing 'pagerank' key in output JSON."
    assert "shortest_paths_from_HUB_001" in data, "Missing 'shortest_paths_from_HUB_001' key in output JSON."


def test_pagerank_mse():
    with open(OUTPUT, "r") as f:
        agent_data = json.load(f).get("pagerank", {})
    golden_data = expected_results()["pagerank"]

    sq_errors = []
    for node_id, golden_val in golden_data.items():
        agent_val = agent_data.get(node_id, 0.0)
        sq_errors.append((golden_val - agent_val) ** 2)

    mse = sum(sq_errors) / len(sq_errors) if sq_errors else 1.0
    assert mse <= 1e-6, f"PageRank MSE is {mse}, which exceeds the threshold of 1e-6."


def test_shortest_paths():
    with open(OUTPUT, "r") as f:
        agent_data = json.load(f).get("shortest_paths_from_HUB_001", {})
    golden_data = expected_results()["shortest_paths_from_HUB_001"]

    for node_id, golden_val in golden_data.items():
        agent_val = agent_data.get(node_id)
        assert agent_val is not None, f"Missing shortest path for node {node_id}."
        assert abs(golden_val - agent_val) <= 1e-3, (
            f"Shortest path for node {node_id} is {agent_val}, expected {golden_val}."
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
