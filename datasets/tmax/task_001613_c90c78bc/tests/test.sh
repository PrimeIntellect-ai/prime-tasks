#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import pathlib
import random
import secrets
import shutil
import subprocess
import pytest

PROJECT = pathlib.Path("/home/user/graph_analyzer")
NODES = pathlib.Path("/home/user/dataset/nodes.jsonl")
EDGES = pathlib.Path("/home/user/dataset/edges.jsonl")
RESULTS = pathlib.Path("/home/user/results")
OUTPUT = RESULTS / "gaps.json"


def test_results_file_exists():
    path = "/home/user/results/gaps.json"
    assert os.path.isfile(path), f"{path} does not exist. Did you create the results directory and output file?"


def test_results_content_and_sorting():
    path = "/home/user/results/gaps.json"
    assert os.path.isfile(path), f"{path} does not exist."

    with open(path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{path} does not contain valid JSON.")

    expected = [
        {"x": "N3", "y": "N1", "z": "N2"},
        {"x": "N3", "y": "N1", "z": "N4"},
        {"x": "N5", "y": "N6", "z": "N7"}
    ]

    assert isinstance(data, list), "The root of the JSON file must be an array."

    # Check that keys are exactly "x", "y", "z" for each object
    for i, item in enumerate(data):
        assert isinstance(item, dict), f"Element at index {i} is not a JSON object."
        assert set(item.keys()) == {"x", "y", "z"}, f"Element at index {i} has incorrect keys: {list(item.keys())}. Expected exactly ['x', 'y', 'z']."

    # The list must match exactly, which also validates the sorting requirement
    assert data == expected, f"Output JSON data does not match the expected result or is not sorted correctly.\nExpected: {expected}\nGot: {data}"


def derive_expected(nodes, edges):
    authors = {
        node["id"]: node["field"]
        for node in nodes
        if node.get("type") == "Author"
    }
    cites = {
        (edge["src"], edge["dst"])
        for edge in edges
        if edge.get("rel") == "CITES"
    }
    triples = set()
    for x, y in cites:
        for y2, z in cites:
            if y != y2 or len({x, y, z}) != 3:
                continue
            if x not in authors or y not in authors or z not in authors:
                continue
            if not (authors[x] == authors[y] == authors[z]):
                continue
            if (x, z) not in cites:
                triples.add((x, y, z))
    return [{"x": x, "y": y, "z": z} for x, y, z in sorted(triples)]


def make_case(round_number):
    token = secrets.token_hex(10)
    ids = [f"id_{token}_{i:02d}" for i in range(12)]
    field_a = f"field_{secrets.token_hex(5)}"
    field_b = f"field_{secrets.token_hex(5)}"
    nodes = []
    for i, node_id in enumerate(ids):
        if i == 10:
            nodes.append({"id": node_id, "type": "Paper", "field": field_a})
        elif i >= 7:
            nodes.append({"id": node_id, "type": "Author", "field": field_b})
        else:
            nodes.append({"id": node_id, "type": "Author", "field": field_a, "extra": i})

    rng = random.SystemRandom()
    cite_pairs = set()
    for i in range(len(ids)):
        for j in range(len(ids)):
            if i != j and rng.random() < 0.13:
                cite_pairs.add((i, j))

    # Guaranteed gaps in both fields, plus a direct edge that must suppress one path.
    cite_pairs.update({(0, 1), (1, 2), (1, 3), (7, 8), (8, 9), (10, 0)})
    cite_pairs.discard((0, 2))
    cite_pairs.add((0, 3))
    cite_pairs.discard((7, 9))
    if round_number == 1:
        cite_pairs.update({(4, 5), (5, 6)})
        cite_pairs.discard((4, 6))

    edges = [
        {"src": ids[i], "dst": ids[j], "rel": "CITES"}
        for i, j in cite_pairs
    ]
    edges.extend([
        {"src": ids[2], "dst": ids[4], "rel": f"RELATED_{token}"},
        {"src": ids[3], "dst": ids[10], "rel": "MENTIONS"},
        {"src": ids[6], "dst": ids[7], "rel": "CITES"},
    ])
    rng.shuffle(nodes)
    rng.shuffle(edges)
    return nodes, edges


def write_jsonl(path, records):
    path.write_text("".join(json.dumps(record) + "\n" for record in records), encoding="utf-8")


def validate_output(expected):
    assert OUTPUT.is_file(), "The analyzer did not create /home/user/results/gaps.json."
    try:
        data = json.loads(OUTPUT.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        pytest.fail(f"Analyzer output is not valid JSON: {exc}")
    assert isinstance(data, list), "The root of the generated JSON must be an array."
    for i, item in enumerate(data):
        assert isinstance(item, dict), f"Generated element {i} is not an object."
        assert set(item) == {"x", "y", "z"}, f"Generated element {i} does not have exactly x, y, z."
        assert all(isinstance(item[key], str) for key in ("x", "y", "z")), f"Generated element {i} has a non-string value."
    assert data == expected, f"Analyzer failed a verifier-generated dataset.\nExpected: {expected}\nGot: {data}"


def test_rust_project_and_generated_datasets():
    assert PROJECT.is_dir(), "/home/user/graph_analyzer does not exist or is not a directory."
    manifest = PROJECT / "Cargo.toml"
    assert manifest.is_file(), "The graph_analyzer Cargo.toml is missing."

    metadata_run = subprocess.run(
        ["cargo", "metadata", "--format-version", "1", "--no-deps", "--manifest-path", str(manifest)],
        text=True, capture_output=True, timeout=60
    )
    assert metadata_run.returncode == 0, f"Cargo could not load the Rust project:\n{metadata_run.stdout}\n{metadata_run.stderr}"
    metadata = json.loads(metadata_run.stdout)
    matching_packages = [
        package for package in metadata.get("packages", [])
        if pathlib.Path(package["manifest_path"]).resolve() == manifest.resolve()
    ]
    assert matching_packages, "Cargo metadata did not contain the submitted project."
    package = matching_packages[0]
    assert package.get("name") == "graph_analyzer", "The Cargo package must be named graph_analyzer."
    bin_targets = [target for target in package.get("targets", []) if "bin" in target.get("kind", []) and target.get("name") == "graph_analyzer"]
    assert bin_targets, "The project has no graph_analyzer Rust binary target."
    for target in bin_targets:
        source = pathlib.Path(target["src_path"])
        assert source.is_file() and source.suffix == ".rs" and source.stat().st_size > 0, "The binary target must have a nonempty Rust source file."

    build = subprocess.run(
        ["cargo", "build", "--release", "--manifest-path", str(manifest)],
        cwd=str(PROJECT), text=True, capture_output=True, timeout=180
    )
    assert build.returncode == 0, f"cargo build --release failed:\n{build.stdout}\n{build.stderr}"

    executable = pathlib.Path(metadata["target_directory"]) / "release" / "graph_analyzer"
    assert executable.is_file(), f"Release executable was not produced at {executable}."
    assert os.access(executable, os.X_OK), f"Release artifact {executable} is not executable."

    original_nodes = NODES.read_bytes()
    original_edges = EDGES.read_bytes()
    original_output = OUTPUT.read_bytes() if OUTPUT.is_file() else None
    try:
        for round_number in range(2):
            nodes, edges = make_case(round_number)
            expected = derive_expected(nodes, edges)
            assert expected, "Internal verifier error: generated case has no expected gaps."
            write_jsonl(NODES, nodes)
            write_jsonl(EDGES, edges)
            before_nodes = NODES.read_bytes()
            before_edges = EDGES.read_bytes()

            if RESULTS.exists():
                shutil.rmtree(RESULTS)

            run = subprocess.run(
                [str(executable)], cwd=str(PROJECT), text=True,
                capture_output=True, timeout=60
            )
            assert run.returncode == 0, f"Release analyzer failed on generated data:\n{run.stdout}\n{run.stderr}"
            assert NODES.read_bytes() == before_nodes, "The analyzer modified nodes.jsonl."
            assert EDGES.read_bytes() == before_edges, "The analyzer modified edges.jsonl."
            validate_output(expected)
    finally:
        NODES.write_bytes(original_nodes)
        EDGES.write_bytes(original_edges)
        RESULTS.mkdir(parents=True, exist_ok=True)
        if original_output is None:
            if OUTPUT.exists():
                OUTPUT.unlink()
        else:
            OUTPUT.write_bytes(original_output)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
