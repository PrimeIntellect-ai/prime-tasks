#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import glob
import heapq
import json
import math
import os
import re
import secrets
import subprocess
import tempfile
from collections import Counter, defaultdict

import pytest


def run(cmd, **kwargs):
    return subprocess.run(cmd, capture_output=True, text=True, **kwargs)


def psql(sql, input_text=None):
    result = run(
        ["runuser", "-u", "postgres", "--", "psql", "-X", "-v", "ON_ERROR_STOP=1", "-d", "logistics", "-At", "-F", "\t", "-c", sql],
        input=input_text,
        timeout=60,
    )
    assert result.returncode == 0, f"PostgreSQL command failed:\n{result.stderr}"
    return result.stdout


def psql_script(script):
    result = run(
        ["runuser", "-u", "postgres", "--", "psql", "-X", "-v", "ON_ERROR_STOP=1", "-d", "logistics"],
        input=script,
        timeout=60,
    )
    assert result.returncode == 0, f"PostgreSQL script failed:\n{result.stderr}"


def run_cargo(project, args=(), timeout=240):
    result = run(
        ["runuser", "-u", "user", "--", "cargo", "run", "--quiet", "--", *args],
        cwd=project,
        timeout=timeout,
    )
    return result


def load_results():
    results_path = "/home/user/graph_results.json"
    assert os.path.isfile(results_path), f"Graph results JSON missing at {results_path}"
    try:
        with open(results_path) as f:
            data = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"File at {results_path} is not valid JSON.")

    assert "shortest_path" in data, "Missing 'shortest_path' key in results JSON."
    assert "top_centrality" in data, "Missing 'top_centrality' key in results JSON."
    assert isinstance(data["shortest_path"], list), "'shortest_path' must be a list."
    assert isinstance(data["top_centrality"], list), "'top_centrality' must be a list."
    assert len(data["top_centrality"]) == 5, f"Expected 5 nodes in top centrality, found {len(data['top_centrality'])}."
    for item in data["top_centrality"]:
        assert isinstance(item, dict), "Each centrality entry must be an object."
        assert "node" in item, "Centrality item missing 'node' key."
        assert "degree" in item, "Centrality item missing 'degree' key."
    return data


def expected_shortest_path(edges):
    adjacency = defaultdict(list)
    for _, source, target, cost in edges:
        adjacency[source].append((target, float(cost)))

    start = "DEPOT_ALPHA"
    goal = "DISTRIBUTION_ZETA"
    distances = {start: 0.0}
    previous = {}
    queue = [(0.0, start)]
    while queue:
        distance, node = heapq.heappop(queue)
        if distance != distances.get(node):
            continue
        if node == goal:
            break
        for target, cost in adjacency[node]:
            candidate = distance + cost
            if candidate < distances.get(target, float("inf")):
                distances[target] = candidate
                previous[target] = node
                heapq.heappush(queue, (candidate, target))

    assert goal in distances, "Verifier test graph unexpectedly has no requested path"
    path = [goal]
    while path[-1] != start:
        path.append(previous[path[-1]])
    return list(reversed(path))


def assert_analytics(data, edges):
    assert data["shortest_path"] == expected_shortest_path(edges), "Shortest path is not the weighted path derived from the routes table."

    degrees = Counter()
    for _, source, target, _ in edges:
        degrees[source] += 1
        degrees[target] += 1

    entries = data["top_centrality"]
    nodes = [entry["node"] for entry in entries]
    assert len(set(nodes)) == 5, "Top centrality nodes must be distinct."
    for entry in entries:
        node = entry["node"]
        degree = entry["degree"]
        assert node in degrees, f"Unknown node in centrality output: {node}"
        assert isinstance(degree, (int, float)) and not isinstance(degree, bool), "Degree must be numeric."
        assert degree == degrees[node], f"Incorrect degree for {node}: expected {degrees[node]}, got {degree}"

    omitted = [degree for node, degree in degrees.items() if node not in set(nodes)]
    if omitted:
        assert min(degrees[node] for node in nodes) >= max(omitted), "Returned nodes are not the five highest-degree nodes."


def detect_red_frames():
    probe = run([
        "ffprobe", "-v", "error", "-select_streams", "v:0",
        "-show_entries", "stream=width,height", "-of", "json", "/app/drone_feed.mp4"
    ], timeout=30)
    assert probe.returncode == 0, probe.stderr
    stream = json.loads(probe.stdout)["streams"][0]
    width, height = int(stream["width"]), int(stream["height"])

    decoded = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", "/app/drone_feed.mp4", "-f", "rawvideo", "-pix_fmt", "rgb24", "pipe:1"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
    )
    assert decoded.returncode == 0, decoded.stderr.decode(errors="replace")
    frame_size = width * height * 3
    assert len(decoded.stdout) % frame_size == 0
    red_frames = []
    for frame_number in range(len(decoded.stdout) // frame_size):
        frame = decoded.stdout[frame_number * frame_size:(frame_number + 1) * frame_size]
        red = sum(frame[0::3]) / (width * height)
        green = sum(frame[1::3]) / (width * height)
        blue = sum(frame[2::3]) / (width * height)
        if red > 200 and green < 50 and blue < 50:
            red_frames.append(frame_number)
    assert red_frames == list(range(100, 114)), f"Unexpected source-video red frames: {red_frames}"
    return red_frames


def replace_routes(edges):
    lines = ["TRUNCATE TABLE routes;", "COPY routes (edge_id, source_node, target_node, base_cost) FROM STDIN WITH (FORMAT csv);"]
    for edge_id, source, target, cost in edges:
        lines.append(f"{edge_id},{source},{target},{cost}")
    lines.extend(["\\.", ""])
    psql_script("\n".join(lines))


def restore_raw_routes():
    psql_script("TRUNCATE TABLE routes;\n\\copy routes (edge_id, source_node, target_node, base_cost) FROM '/app/raw_routes.csv' WITH (FORMAT csv, HEADER true)\n")


def read_raw_routes():
    with open("/app/raw_routes.csv", newline="") as f:
        rows = list(csv.DictReader(f))
    return [(int(row["edge_id"]), row["source_node"], row["target_node"], float(row["base_cost"])) for row in rows]


def assert_database_values(edges, multiplier):
    output = psql("SELECT edge_id, base_cost FROM routes ORDER BY edge_id;")
    actual = {}
    for line in output.splitlines():
        if line:
            edge_id, cost = line.split("\t")
            actual[int(edge_id)] = float(cost)
    assert len(actual) == len(edges), f"Expected {len(edges)} updated routes, found {len(actual)}"
    for edge_id, _, _, original_cost in edges:
        expected = original_cost * multiplier
        assert edge_id in actual
        assert math.isclose(actual[edge_id], expected, rel_tol=1e-9, abs_tol=1e-9), f"Incorrect updated cost for edge {edge_id}: expected {expected}, got {actual[edge_id]}"


def assert_schema_and_indexes():
    columns = psql("SELECT column_name, data_type FROM information_schema.columns WHERE table_schema='public' AND table_name='routes' ORDER BY ordinal_position;")
    parsed = [tuple(line.split("\t")) for line in columns.splitlines() if line]
    assert parsed == [
        ("edge_id", "integer"),
        ("source_node", "character varying"),
        ("target_node", "character varying"),
        ("base_cost", "double precision"),
    ], f"routes table has the wrong schema: {parsed}"

    definitions = psql("SELECT indexdef FROM pg_indexes WHERE schemaname='public' AND tablename='routes';").lower().splitlines()
    assert definitions, "No indexes exist on routes."
    assert any("source_node" in definition for definition in definitions), "No route index covers source_node."
    assert any("target_node" in definition for definition in definitions), "No route index covers target_node."


def test_adversarial_corpus_sanitizer():
    evil_files = glob.glob("/app/corpora/evil/*.json")
    clean_files = glob.glob("/app/corpora/clean/*.json")
    assert evil_files, "No evil corpus files found."
    assert clean_files, "No clean corpus files found."

    sanitizer_dir = "/home/user/sanitizer"
    assert os.path.isdir(sanitizer_dir), f"Sanitizer directory missing at {sanitizer_dir}"
    assert os.path.isfile(os.path.join(sanitizer_dir, "Cargo.toml")), "Sanitizer Cargo.toml is missing."
    assert glob.glob(os.path.join(sanitizer_dir, "src", "*.rs")), "Sanitizer Rust source is missing."

    build = run(["runuser", "-u", "user", "--", "cargo", "build"], cwd=sanitizer_dir, timeout=240)
    assert build.returncode == 0, f"Cargo build failed in {sanitizer_dir}:\n{build.stderr}"

    failures = []
    for path in evil_files:
        if run_cargo(sanitizer_dir, (path,)).returncode != 1:
            failures.append(f"evil corpus accepted: {os.path.basename(path)}")
    for path in clean_files:
        if run_cargo(sanitizer_dir, (path,)).returncode != 0:
            failures.append(f"clean corpus rejected: {os.path.basename(path)}")

    with tempfile.TemporaryDirectory(prefix="sanitizer_cases_") as directory:
        cases = [
            ("ordinary_filter_" + secrets.token_hex(5), 0),
            ("region/north-and-status-active", 0),
            ("prefix " + "DROP" + " TABLE routes suffix", 1),
            ("identifier " + "1" + "=" + "1", 1),
            ("assets/" + ".." + "/private/data", 1),
            ("DrOp TaBlE routes", 1),
        ]
        for value, expected in cases:
            path = os.path.join(directory, secrets.token_hex(12) + ".json")
            with open(path, "w") as f:
                json.dump({"query_filter": value}, f)
            result = run_cargo(sanitizer_dir, (path,))
            if result.returncode != expected:
                failures.append(f"dynamic content {value!r} returned {result.returncode}, expected {expected}")

    assert not failures, " ; ".join(failures)


def test_graph_builder_database_video_and_analytics():
    graph_dir = "/home/user/graph_builder"
    assert os.path.isdir(graph_dir), f"Graph-builder directory missing at {graph_dir}"
    assert os.path.isfile(os.path.join(graph_dir, "Cargo.toml")), "Graph-builder Cargo.toml is missing."
    rust_files = glob.glob(os.path.join(graph_dir, "src", "**", "*.rs"), recursive=True)
    assert rust_files, "Graph-builder Rust source is missing."

    source = "\n".join(open(path, errors="replace").read() for path in rust_files)
    assert re.search(r"(?is)update\s+routes.{0,500}\$\d+", source), "The routes UPDATE is not written as a PostgreSQL parameterized query."

    ready = run(["pg_isready"], timeout=15)
    assert ready.returncode == 0, "The local PostgreSQL instance is not running."
    assert_schema_and_indexes()

    build = run(["runuser", "-u", "user", "--", "cargo", "build"], cwd=graph_dir, timeout=300)
    assert build.returncode == 0, f"Cargo build failed in {graph_dir}:\n{build.stderr}"

    red_frames = detect_red_frames()
    multiplier = len(red_frames) * 1.5

    synthetic = [
        (0, "DEPOT_ALPHA", "A", 1.0),
        (1, "A", "DISTRIBUTION_ZETA", 20.0),
        (2, "DEPOT_ALPHA", "B", 2.0),
        (3, "B", "C", 2.0),
        (4, "C", "DISTRIBUTION_ZETA", 2.0),
        (5, "A", "C", 1.0),
        (6, "B", "E", 1.0),
        (7, "E", "F", 1.0),
        (8, "F", "DISTRIBUTION_ZETA", 20.0),
        (9, "C", "G", 1.0),
        (10, "G", "H", 1.0),
        (11, "H", "DISTRIBUTION_ZETA", 1.0),
    ]
    replace_routes(synthetic)
    execution = run_cargo(graph_dir, timeout=300)
    assert execution.returncode == 0, f"Graph builder failed on a valid routes table:\n{execution.stderr}"
    assert_database_values(synthetic, multiplier)
    assert_analytics(load_results(), synthetic)

    raw_edges = read_raw_routes()
    assert len(raw_edges) == 10000, f"Raw route dataset should contain 10000 edges, found {len(raw_edges)}"
    restore_raw_routes()
    execution = run_cargo(graph_dir, timeout=300)
    assert execution.returncode == 0, f"Graph builder failed on the supplied dataset:\n{execution.stderr}"
    assert_database_values(raw_edges, multiplier)
    assert_analytics(load_results(), raw_edges)
    assert_schema_and_indexes()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
