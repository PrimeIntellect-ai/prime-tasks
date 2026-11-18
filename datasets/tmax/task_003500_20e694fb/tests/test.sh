#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import subprocess
from collections import defaultdict

import pytest

PROJECT = "/home/user/influencer_calc"
EDGES_PATH = "/home/user/edges.csv"
RESULT_PATH = "/home/user/result.json"


def expected_result(edges_path):
    adj = defaultdict(set)
    with open(edges_path, "r") as f:
        f.readline()
        for line in f:
            if not line.strip():
                continue
            u, v = map(int, line.strip().split(","))
            adj[u].add(v)
            adj[v].add(u)

    scores = []
    for node in adj:
        friends = adj[node]
        fof = set()
        for friend in friends:
            fof.update(adj[friend])
        fof -= friends
        fof.discard(node)
        scores.append((node, len(fof)))

    scores.sort(key=lambda x: (-x[1], x[0]))
    return [[n, score] for n, score in scores[:5]]


def load_result():
    assert os.path.isfile(RESULT_PATH), f"Output file {RESULT_PATH} does not exist."
    with open(RESULT_PATH, "r") as f:
        try:
            result = json.load(f)
        except json.JSONDecodeError:
            assert False, f"File {RESULT_PATH} is not valid JSON."
    assert isinstance(result, list), f"Expected JSON array, got {type(result).__name__}"
    assert len(result) == 5, f"Expected exactly 5 results, got {len(result)}"
    try:
        return [list(item) for item in result]
    except TypeError:
        assert False, "Each result must be a two-element JSON array."


def build_rust_binary():
    metadata_proc = subprocess.run(
        ["cargo", "metadata", "--format-version", "1", "--no-deps"],
        cwd=PROJECT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
    )
    assert metadata_proc.returncode == 0, f"cargo metadata failed:\n{metadata_proc.stderr}"
    metadata = json.loads(metadata_proc.stdout)

    manifest = os.path.realpath(os.path.join(PROJECT, "Cargo.toml"))
    packages = [p for p in metadata["packages"] if os.path.realpath(p["manifest_path"]) == manifest]
    assert len(packages) == 1, "Could not identify the Rust package in Cargo.toml."
    package = packages[0]
    bins = [t for t in package["targets"] if "bin" in t.get("kind", [])]
    assert bins, "The Cargo project has no Rust binary target."

    default_run = package.get("default_run")
    if default_run:
        selected = [t for t in bins if t["name"] == default_run]
        assert len(selected) == 1, "Cargo default-run does not identify a binary target."
        bin_name = selected[0]["name"]
    else:
        assert len(bins) == 1, "Multiple binaries exist but Cargo.toml has no default-run target."
        bin_name = bins[0]["name"]

    build_proc = subprocess.run(
        ["cargo", "build", "--release", "--bin", bin_name, "--message-format=json-render-diagnostics"],
        cwd=PROJECT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=240,
    )
    assert build_proc.returncode == 0, (
        f"Rust project did not compile successfully:\n{build_proc.stdout}\n{build_proc.stderr}"
    )

    executables = []
    for line in build_proc.stdout.splitlines():
        try:
            message = json.loads(line)
        except json.JSONDecodeError:
            continue
        if (
            message.get("reason") == "compiler-artifact"
            and message.get("package_id") == package["id"]
            and message.get("target", {}).get("name") == bin_name
            and "bin" in message.get("target", {}).get("kind", [])
            and message.get("executable")
        ):
            executables.append(message["executable"])

    assert executables, "Cargo did not produce an executable Rust binary."
    binary = executables[-1]
    assert os.path.isfile(binary), f"Built executable {binary} does not exist."
    assert os.access(binary, os.X_OK), f"Built artifact {binary} is not executable."
    return binary


def run_binary(binary):
    if os.path.exists(RESULT_PATH):
        os.remove(RESULT_PATH)
    proc = subprocess.run(
        [binary],
        cwd=PROJECT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
    )
    assert proc.returncode == 0, (
        f"The compiled Rust program failed with exit code {proc.returncode}:\n"
        f"stdout:\n{proc.stdout}\nstderr:\n{proc.stderr}"
    )
    assert os.path.isfile(RESULT_PATH), (
        f"The compiled Rust program did not create {RESULT_PATH}."
    )


@pytest.fixture(scope="session", autouse=True)
def compiled_program():
    assert os.path.isdir(PROJECT), f"Rust project directory {PROJECT} does not exist."
    assert os.path.isfile(os.path.join(PROJECT, "Cargo.toml")), (
        f"Cargo.toml not found in {PROJECT}. Is it a valid Rust project?"
    )
    binary = build_rust_binary()
    run_binary(binary)
    return binary


def test_influencer_calc_project_exists():
    path = "/home/user/influencer_calc"
    assert os.path.isdir(path), f"Rust project directory {path} does not exist."
    assert os.path.isfile(os.path.join(path, "Cargo.toml")), f"Cargo.toml not found in {path}. Is it a valid Rust project?"


def test_result_json_exists():
    path = "/home/user/result.json"
    assert os.path.isfile(path), f"Output file {path} does not exist."


def test_result_json_content():
    assert os.path.isfile(EDGES_PATH), f"Input file {EDGES_PATH} missing."
    expected_top_5 = expected_result(EDGES_PATH)
    actual_top_5 = load_result()
    assert actual_top_5 == expected_top_5, f"Expected {expected_top_5}, but got {actual_top_5}"


def test_compiled_program_handles_unseen_graphs(compiled_program):
    with open(EDGES_PATH, "rb") as f:
        original_edges = f.read()
    original_result = None
    if os.path.isfile(RESULT_PATH):
        with open(RESULT_PATH, "rb") as f:
            original_result = f.read()

    rng = random.SystemRandom()
    try:
        for _ in range(2):
            nodes = rng.sample(range(10000, 900000), 36)
            shuffled = nodes[:]
            rng.shuffle(shuffled)
            edges = set()

            # A random spanning tree ensures every generated node is represented.
            for i in range(1, len(shuffled)):
                parent = shuffled[rng.randrange(i)]
                edges.add(tuple(sorted((shuffled[i], parent))))

            while len(edges) < 115:
                u, v = rng.sample(nodes, 2)
                edges.add(tuple(sorted((u, v))))

            with open(EDGES_PATH, "w") as f:
                f.write("source,target\n")
                for u, v in sorted(edges):
                    f.write(f"{u},{v}\n")

            expected = expected_result(EDGES_PATH)
            run_binary(compiled_program)
            actual = load_result()
            assert actual == expected, f"Rust program failed an unseen graph: expected {expected}, got {actual}"
    finally:
        with open(EDGES_PATH, "wb") as f:
            f.write(original_edges)
        if original_result is None:
            if os.path.exists(RESULT_PATH):
                os.remove(RESULT_PATH)
        else:
            with open(RESULT_PATH, "wb") as f:
                f.write(original_result)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
