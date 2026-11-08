#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import subprocess
import tempfile
import uuid

import pytest

VENDORED_DIR = "/app/vendored/graph-mapper"
VALIDATOR_DIR = "/home/user/record-validator"


def run_command(cmd, cwd=None, timeout=180):
    return subprocess.run(
        cmd,
        cwd=cwd,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=timeout,
    )


def require_success(result, description):
    assert result.returncode == 0, (
        f"{description} failed with exit code {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def cargo_metadata(manifest):
    result = run_command([
        "cargo", "metadata", "--format-version", "1", "--no-deps",
        "--manifest-path", manifest,
    ])
    require_success(result, f"cargo metadata for {manifest}")
    return json.loads(result.stdout)


def parse_output(stdout, expected_names):
    lines = stdout.splitlines()
    assert len(lines) == len(expected_names), (
        f"Expected exactly {len(expected_names)} output lines, got {len(lines)}: {lines!r}"
    )

    results = {}
    pattern = re.compile(r"^(ACCEPT|REJECT) ([^/\\\s]+\.json)$")
    for line in lines:
        match = pattern.fullmatch(line)
        assert match, f"Invalid output line (expected exact format): {line!r}"
        status, filename = match.groups()
        assert filename not in results, f"Duplicate output for {filename}"
        assert filename in expected_names, f"Output mentions unexpected file {filename}"
        results[filename] = status

    assert set(results) == set(expected_names), "Output did not cover every JSON file exactly once"
    return results


def run_validator(directory):
    result = run_command(
        ["cargo", "run", "--quiet", "--release", "--", directory],
        cwd=VALIDATOR_DIR,
    )
    require_success(result, f"validator execution on {directory}")
    names = sorted(name for name in os.listdir(directory) if name.endswith(".json"))
    return parse_output(result.stdout, names)


def expected_valid(record):
    nodes = record["graph"]["nodes"]
    edges = record["graph"]["edges"]
    node_types = {node["id"]: node["type"] for node in nodes}
    node_ids = set(node_types)
    adjacency = {node_id: [] for node_id in node_ids}
    for edge in edges:
        adjacency.setdefault(edge["source"], []).append(edge["target"])

    colors = {}

    def visit(node):
        color = colors.get(node, 0)
        if color == 1:
            return True
        if color == 2:
            return False
        colors[node] = 1
        for target in adjacency.get(node, []):
            if visit(target):
                return True
        colors[node] = 2
        return False

    if any(visit(node_id) for node_id in node_ids if colors.get(node_id, 0) == 0):
        return False

    doc_id = record["document"]["doc_id"]
    refs = record["document"]["dataset_refs"]
    if node_types.get(doc_id) != "Document":
        return False
    if any(node_types.get(ref) != "Dataset" for ref in refs):
        return False

    reachable = {doc_id}
    stack = [doc_id]
    while stack:
        current = stack.pop()
        for target in adjacency.get(current, []):
            if target not in reachable:
                reachable.add(target)
                stack.append(target)
    return all(ref in reachable for ref in refs)


def make_record(doc_id, refs, typed_nodes, edge_pairs):
    return {
        "document": {"doc_id": doc_id, "dataset_refs": refs},
        "graph": {
            "nodes": [{"id": node_id, "type": node_type} for node_id, node_type in typed_nodes],
            "edges": [
                {"source": source, "target": target, "relation": "rel_" + uuid.uuid4().hex[:8]}
                for source, target in edge_pairs
            ],
        },
    }


def test_vendored_library_compiles_and_has_real_serde_dependency():
    assert os.path.isdir(VENDORED_DIR), f"Vendored library directory {VENDORED_DIR} does not exist."
    manifest = os.path.join(VENDORED_DIR, "Cargo.toml")
    assert os.path.isfile(manifest), f"{manifest} does not exist."

    with open(manifest, "r") as handle:
        content = handle.read()
    assert "serde" in content, "The 'serde' dependency is still missing from graph-mapper/Cargo.toml."

    metadata = cargo_metadata(manifest)
    package = next(
        (p for p in metadata["packages"] if os.path.realpath(p["manifest_path"]) == os.path.realpath(manifest)),
        None,
    )
    assert package is not None, "graph-mapper package was not found in cargo metadata"
    serde_dependencies = [d for d in package["dependencies"] if d["name"] == "serde"]
    assert serde_dependencies, "serde appears only as text and is not a Cargo dependency"
    assert any(not d.get("optional", False) and d.get("kind") == "normal" for d in serde_dependencies), (
        "serde must be an enabled normal dependency"
    )

    result = run_command(["cargo", "check"], cwd=VENDORED_DIR)
    require_success(result, "graph-mapper cargo check")
    assert "error" not in result.stderr.lower(), f"graph-mapper failed to compile:\n{result.stderr}"


def test_record_validator_compiles_and_depends_on_local_graph_mapper():
    assert os.path.isdir(VALIDATOR_DIR), f"Validator directory {VALIDATOR_DIR} does not exist."
    manifest = os.path.join(VALIDATOR_DIR, "Cargo.toml")
    assert os.path.isfile(manifest), f"{manifest} does not exist."

    metadata = cargo_metadata(manifest)
    package = next(
        (p for p in metadata["packages"] if os.path.realpath(p["manifest_path"]) == os.path.realpath(manifest)),
        None,
    )
    assert package is not None, "record-validator package was not found in cargo metadata"
    graph_dependencies = [
        d for d in package["dependencies"]
        if d["name"] == "graph-mapper"
        and d.get("path")
        and os.path.realpath(d["path"]) == os.path.realpath(VENDORED_DIR)
        and d.get("kind") == "normal"
        and not d.get("optional", False)
        and d.get("target") is None
    ]
    assert graph_dependencies, "record-validator must have an enabled normal path dependency on local graph-mapper"

    result = run_command(["cargo", "build", "--release"], cwd=VALIDATOR_DIR)
    require_success(result, "record-validator release build")
    assert "error" not in result.stderr.lower(), f"record-validator failed to compile:\n{result.stderr}"


def test_validator_on_supplied_corpora():
    clean_dir = "/app/data/clean_corpus"
    evil_dir = "/app/data/evil_corpus"

    clean_results = run_validator(clean_dir)
    rejected = [name for name, status in clean_results.items() if status != "ACCEPT"]
    assert not rejected, f"Clean files rejected instead of accepted: {', '.join(rejected)}"

    evil_results = run_validator(evil_dir)
    accepted = [name for name, status in evil_results.items() if status != "REJECT"]
    assert not accepted, f"Evil files accepted instead of rejected: {', '.join(accepted)}"


def test_validator_on_generated_unseen_records():
    case_dir = tempfile.mkdtemp(prefix="record_validator_cases_")
    token = lambda prefix: prefix + "_" + uuid.uuid4().hex
    cases = []

    # Valid direct, transitive, and empty-reference records.
    d, a, b = token("doc"), token("mid"), token("ds")
    cases.append(make_record(d, [b], [(d, "Document"), (a, "Entity"), (b, "Dataset")], [(d, a), (a, b)]))
    d, a, b = token("doc"), token("ds"), token("ds")
    cases.append(make_record(d, [a, b], [(d, "Document"), (a, "Dataset"), (b, "Dataset")], [(d, a), (d, b)]))
    d, x = token("doc"), token("other")
    cases.append(make_record(d, [], [(d, "Document"), (x, "Entity")], []))

    # Each invalid record isolates a required rule.
    d, a = token("doc"), token("ds")
    cases.append(make_record(d, [a], [(d, "Document"), (a, "Dataset")], [(d, a), (a, a)]))
    d, a, x, y = token("doc"), token("ds"), token("x"), token("y")
    cases.append(make_record(d, [a], [(d, "Document"), (a, "Dataset"), (x, "Entity"), (y, "Entity")], [(d, a), (x, y), (y, x)]))
    d, a = token("doc"), token("ds")
    cases.append(make_record(d, [a], [(d, "Entity"), (a, "Dataset")], [(d, a)]))
    d, a = token("missing_doc"), token("ds")
    cases.append(make_record(d, [a], [(a, "Dataset")], []))
    d, a = token("doc"), token("ds")
    cases.append(make_record(d, [a], [(d, "Document"), (a, "Entity")], [(d, a)]))
    d, a = token("doc"), token("missing_ds")
    cases.append(make_record(d, [a], [(d, "Document")], []))
    d, a, x = token("doc"), token("ds"), token("other")
    cases.append(make_record(d, [a], [(d, "Document"), (a, "Dataset"), (x, "Entity")], [(d, x)]))

    # Additional randomized graphs make classifications depend on parsed content,
    # not on a fixed set of fixture names.
    rng = random.SystemRandom()
    for _ in range(12):
        count = rng.randint(4, 8)
        ids = [token("node") for _ in range(count)]
        doc = ids[0] if rng.random() < 0.85 else token("absent_doc")
        typed = []
        for index, node_id in enumerate(ids):
            if index == 0:
                node_type = rng.choice(["Document", "Document", "Entity"])
            else:
                node_type = rng.choice(["Dataset", "Entity", "Dataset"])
            typed.append((node_id, node_type))
        refs = rng.sample(ids[1:], rng.randint(0, min(3, count - 1)))
        if rng.random() < 0.2:
            refs.append(token("absent_ref"))
        edges = []
        for source in ids:
            for target in ids:
                if source != target and rng.random() < 0.16:
                    edges.append((source, target))
        if rng.random() < 0.15:
            chosen = rng.choice(ids)
            edges.append((chosen, chosen))
        cases.append(make_record(doc, refs, typed, edges))

    expected = {}
    for record in cases:
        filename = "case_" + uuid.uuid4().hex + ".json"
        with open(os.path.join(case_dir, filename), "w") as handle:
            json.dump(record, handle)
        expected[filename] = "ACCEPT" if expected_valid(record) else "REJECT"

    with open(os.path.join(case_dir, "ignore_" + uuid.uuid4().hex + ".txt"), "w") as handle:
        handle.write("not a JSON fixture")

    assert "ACCEPT" in expected.values() and "REJECT" in expected.values()
    actual = run_validator(case_dir)
    assert actual == expected, f"Generated-record classifications differ: expected {expected}, got {actual}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
