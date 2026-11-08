#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import random
import secrets
import subprocess
import tempfile
from collections import deque

import pytest

PROJECT = "/home/user/dataset_filter"
MANIFEST = os.path.join(PROJECT, "Cargo.toml")
VENDORED = os.path.realpath("/app/vendored/dataset_graph")


def run_binary(binary, schema, log):
    try:
        return subprocess.run(
            [binary, schema, log], capture_output=True, timeout=5
        ).returncode
    except subprocess.TimeoutExpired:
        pytest.fail(f"validator timed out for {os.path.basename(log)}")


def shortest_distance(schema, source, target):
    adjacency = {node: [] for node in schema["nodes"]}
    for left, right in schema["edges"]:
        adjacency.setdefault(left, []).append(right)
        adjacency.setdefault(right, []).append(left)
    if source not in adjacency or target not in adjacency:
        return None
    queue = deque([(source, 0)])
    visited = {source}
    while queue:
        node, distance = queue.popleft()
        if node == target:
            return distance
        for neighbor in adjacency.get(node, []):
            if neighbor not in visited:
                visited.add(neighbor)
                queue.append((neighbor, distance + 1))
    return None


def test_dataset_filter_binary():
    # Preserve the original artifact, schema, and fixed-corpus assertions.
    binary_path = os.path.join(PROJECT, "target/debug/dataset_filter")
    if not os.path.exists(binary_path):
        binary_path = os.path.join(PROJECT, "target/release/dataset_filter")
    assert os.path.exists(binary_path), (
        "Rust binary not found at /home/user/dataset_filter/target/debug/"
        "dataset_filter (or release)"
    )
    assert os.path.isfile(binary_path) and os.access(binary_path, os.X_OK)

    schema_path = "/app/graph_schema.json"
    assert os.path.exists(schema_path), f"Schema file missing: {schema_path}"

    clean_dir = "/app/corpus/clean"
    evil_dir = "/app/corpus/evil"
    clean_corpus = glob.glob(os.path.join(clean_dir, "*"))
    evil_corpus = glob.glob(os.path.join(evil_dir, "*"))
    assert len(clean_corpus) > 0, f"No files found in clean corpus directory: {clean_dir}"
    assert len(evil_corpus) > 0, f"No files found in evil corpus directory: {evil_dir}"

    clean_modified = []
    for clean_file in clean_corpus:
        if run_binary(binary_path, schema_path, clean_file) != 0:
            clean_modified.append(os.path.basename(clean_file))

    evil_bypassed = []
    for evil_file in evil_corpus:
        if run_binary(binary_path, schema_path, evil_file) == 0:
            evil_bypassed.append(os.path.basename(evil_file))

    errors = []
    if evil_bypassed:
        errors.append(
            f"{len(evil_bypassed)} of {len(evil_corpus)} evil bypassed: "
            + ", ".join(evil_bypassed)
        )
    if clean_modified:
        errors.append(
            f"{len(clean_modified)} of {len(clean_corpus)} clean modified: "
            + ", ".join(clean_modified)
        )
    assert not errors, " | ".join(errors)

    # Verify this is a buildable Rust project using the required local dependency.
    assert os.path.isfile(MANIFEST), f"Missing Rust manifest: {MANIFEST}"
    metadata_result = subprocess.run(
        ["cargo", "metadata", "--format-version", "1", "--manifest-path", MANIFEST],
        capture_output=True,
        text=True,
        timeout=120,
    )
    assert metadata_result.returncode == 0, metadata_result.stderr
    metadata = json.loads(metadata_result.stdout)
    project_manifest = os.path.realpath(MANIFEST)
    package = next(
        (p for p in metadata["packages"] if os.path.realpath(p["manifest_path"]) == project_manifest),
        None,
    )
    assert package is not None, "dataset_filter package absent from cargo metadata"
    graph_dependencies = [d for d in package["dependencies"] if d["name"] == "dataset_graph"]
    assert graph_dependencies, "dataset_graph is not declared as a dependency"
    assert any(d.get("path") and os.path.realpath(d["path"]) == VENDORED for d in graph_dependencies), (
        "dataset_graph must use the local /app/vendored/dataset_graph package"
    )

    rust_source = ""
    source_root = os.path.join(PROJECT, "src")
    assert os.path.isdir(source_root), "Rust source directory is missing"
    for root, _, files in os.walk(source_root):
        for filename in files:
            if filename.endswith(".rs"):
                with open(os.path.join(root, filename), encoding="utf-8") as handle:
                    rust_source += handle.read() + "\n"
    assert "dataset_graph" in rust_source, "Rust source does not use dataset_graph"
    assert "from_json" in rust_source, "Rust source does not call Graph::from_json"
    assert "shortest_path" in rust_source, "Rust source does not call shortest_path"

    build = subprocess.run(
        ["cargo", "build", "--manifest-path", MANIFEST],
        capture_output=True,
        text=True,
        timeout=180,
    )
    assert build.returncode == 0, f"Rust project does not build:\n{build.stderr}"
    binary_path = os.path.join(PROJECT, "target/debug/dataset_filter")
    assert os.path.isfile(binary_path) and os.access(binary_path, os.X_OK)

    # Wrong argument counts must not be accepted.
    for arguments in ([], [schema_path], [schema_path, clean_corpus[0], clean_corpus[0]]):
        result = subprocess.run([binary_path] + arguments, capture_output=True, timeout=5)
        assert result.returncode != 0, f"accepted wrong argument count: {len(arguments)}"

    # Exercise fresh schemas and logs at unpredictable, label-neutral paths. Expected
    # answers are independently derived from each generated graph.
    rng = random.SystemRandom()
    with tempfile.TemporaryDirectory(prefix="validator_cases_") as temp_dir:
        cases = []
        for schema_index in range(5):
            nodes = ["N" + secrets.token_hex(6) for _ in range(7)]
            chain = nodes[:6]
            edges = [[chain[i], chain[i + 1]] for i in range(5)]
            for edge in edges:
                if rng.choice([True, False]):
                    edge.reverse()
            rng.shuffle(edges)
            schema = {"nodes": nodes, "edges": edges}
            generated_schema = os.path.join(temp_dir, secrets.token_hex(10) + ".json")
            with open(generated_schema, "w", encoding="utf-8") as handle:
                json.dump(schema, handle)

            # Cover every pair, including distance 0, distances 1-3, distance >3,
            # and the disconnected node. The oracle is computed from the schema.
            for source in nodes:
                for target in nodes:
                    distance = shortest_distance(schema, source, target)
                    expected = 0 if distance is not None and distance <= 3 else 1
                    log = {
                        "experiment_id": "EXP-" + secrets.token_hex(5),
                        "timestamp": f"{rng.randint(1990, 2024):04d}-10-01T12:00:00Z",
                        "source_node": source,
                        "target_node": target,
                        "metrics": {},
                    }
                    cases.append((generated_schema, log, expected))

            # Future year and every independently missing required field must fail.
            base = {
                "experiment_id": "EXP-" + secrets.token_hex(5),
                "timestamp": "2024-01-01T00:00:00Z",
                "source_node": chain[0],
                "target_node": chain[1],
                "metrics": {},
            }
            future = dict(base)
            future["timestamp"] = f"{rng.randint(2025, 2099)}-01-01T00:00:00Z"
            cases.append((generated_schema, future, 1))
            unknown = dict(base)
            unknown["target_node"] = "UNKNOWN_" + secrets.token_hex(5)
            cases.append((generated_schema, unknown, 1))
            for required in ("experiment_id", "timestamp", "source_node", "target_node"):
                missing = dict(base)
                del missing[required]
                cases.append((generated_schema, missing, 1))

        rng.shuffle(cases)
        for generated_schema, log, expected in cases:
            log_path = os.path.join(temp_dir, secrets.token_hex(12) + ".json")
            with open(log_path, "w", encoding="utf-8") as handle:
                json.dump(log, handle)
            actual = run_binary(binary_path, generated_schema, log_path)
            assert actual == expected, (
                f"wrong exit code {actual}, expected {expected}, for generated case "
                f"schema={generated_schema} log={log_path}"
            )

        malformed_path = os.path.join(temp_dir, secrets.token_hex(12) + ".json")
        with open(malformed_path, "w", encoding="utf-8") as handle:
            handle.write('{"experiment_id":')
        assert run_binary(binary_path, generated_schema, malformed_path) == 1, (
            "malformed JSON must exit with code 1"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
