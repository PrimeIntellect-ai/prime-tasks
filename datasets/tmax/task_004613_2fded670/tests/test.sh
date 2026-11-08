#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import py_compile
import random
import secrets
import subprocess
import tempfile
from collections import deque

import pytest

SCRIPT_PATH = "/home/user/detect_violations.py"
VENDOR_ROOT = os.path.realpath("/app/networkx-vendored")


def test_networkx_installed():
    """Verify that networkx is properly installed and importable from the vendored tree."""
    try:
        import networkx as nx
        assert hasattr(nx, "node_link_graph"), "networkx is installed but missing node_link_graph; installation may be corrupted."
    except ImportError:
        pytest.fail("networkx is not installed or importable. The setup.py fix or installation failed.")

    origin = os.path.realpath(nx.__file__)
    assert os.path.commonpath([origin, VENDOR_ROOT]) == VENDOR_ROOT, (
        f"Imported networkx from {origin}, not from {VENDOR_ROOT}."
    )
    py_compile.compile("/app/networkx-vendored/setup.py", doraise=True)


def test_script_exists():
    """Verify the student created the detection script at the correct path."""
    assert os.path.isfile(SCRIPT_PATH), f"The script {SCRIPT_PATH} does not exist."


def run_detector(input_dir):
    with tempfile.NamedTemporaryFile(mode="r+", delete=False) as tmp_out:
        out_file = tmp_out.name
    try:
        result = subprocess.run(
            ["python3", SCRIPT_PATH, input_dir, out_file],
            capture_output=True,
            text=True,
            timeout=20,
        )
        assert result.returncode == 0, f"Script failed execution. STDERR:\n{result.stderr}"
        with open(out_file, "r") as f:
            return [line.strip() for line in f if line.strip()]
    finally:
        if os.path.exists(out_file):
            os.remove(out_file)


def test_detector_evil_corpus():
    """Verify the script correctly flags all files in the evil corpus."""
    evil_dir = "/app/corpus/evil"
    flagged = set(run_detector(evil_dir))
    evil_files = set(f for f in os.listdir(evil_dir) if f.endswith(".json"))
    missed = evil_files - flagged
    assert not missed, f"{len(missed)} of {len(evil_files)} evil bypassed detection. Missed files: {', '.join(missed)}"


def test_detector_clean_corpus():
    """Verify the script correctly ignores all files in the clean corpus."""
    clean_dir = "/app/corpus/clean"
    flagged = set(run_detector(clean_dir))
    clean_files = set(f for f in os.listdir(clean_dir) if f.endswith(".json"))
    false_positives = clean_files & flagged
    assert not false_positives, f"{len(false_positives)} of {len(clean_files)} clean modified/flagged incorrectly. Offending files: {', '.join(false_positives)}"


def has_violation(graph_data):
    statuses = {node["id"]: node.get("status") for node in graph_data["nodes"]}
    adjacency = {node_id: [] for node_id in statuses}
    for edge in graph_data["links"]:
        adjacency.setdefault(edge["source"], []).append(edge["target"])

    cleared = {node_id for node_id, status in statuses.items() if status == "cleared"}
    for source, status in statuses.items():
        if status != "sanctioned":
            continue
        queue = deque([(source, 0)])
        seen = {source}
        while queue:
            node, distance = queue.popleft()
            if node in cleared and distance <= 3:
                return True
            if distance == 3:
                continue
            for neighbor in adjacency.get(node, []):
                if neighbor not in seen:
                    seen.add(neighbor)
                    queue.append((neighbor, distance + 1))
    return False


def make_graph(distance, reverse=False):
    token = secrets.token_hex(5)
    if distance is None:
        ids = [f"s_{token}", f"c_{token}"]
        edges = []
    else:
        ids = [f"n_{token}_{i}" for i in range(distance + 1)]
        edges = [(ids[i], ids[i + 1]) for i in range(distance)]
        if reverse:
            edges = [(target, source) for source, target in edges]

    nodes = [{"id": node_id} for node_id in ids]
    nodes[0]["status"] = "sanctioned"
    nodes[-1]["status"] = "cleared"

    # Add an unrelated directed component so solutions must inspect statuses and reachability.
    extra_a = f"x_{token}"
    extra_b = f"y_{token}"
    nodes.extend([{"id": extra_a}, {"id": extra_b}])
    edges.append((extra_a, extra_b))

    return {
        "directed": True,
        "multigraph": False,
        "graph": {},
        "nodes": nodes,
        "links": [{"source": source, "target": target} for source, target in edges],
    }


def test_detector_on_generated_mixed_corpus():
    """Exercise the detector on a fresh mixed corpus whose answers are derived here."""
    cases = [
        make_graph(1), make_graph(2), make_graph(3),
        make_graph(4), make_graph(5), make_graph(None),
        make_graph(1, reverse=True), make_graph(2, reverse=True),
        make_graph(3, reverse=True), make_graph(4, reverse=True),
    ]
    random.SystemRandom().shuffle(cases)

    with tempfile.TemporaryDirectory(prefix="transaction_networks_") as input_dir:
        expected = set()
        all_names = set()
        for graph_data in cases:
            filename = f"network_{secrets.token_hex(8)}.json"
            all_names.add(filename)
            with open(os.path.join(input_dir, filename), "w") as f:
                json.dump(graph_data, f)
            if has_violation(graph_data):
                expected.add(filename)

        assert expected and expected != all_names, "Generated corpus must contain both violating and compliant graphs."
        reported_lines = run_detector(input_dir)
        assert len(reported_lines) == len(set(reported_lines)), "Output contains duplicate filenames."
        assert set(reported_lines) == expected, (
            f"Incorrect generated-corpus result. Expected {sorted(expected)}, got {sorted(set(reported_lines))}."
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
