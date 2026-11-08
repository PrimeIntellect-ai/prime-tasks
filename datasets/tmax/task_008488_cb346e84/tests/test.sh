#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import stat
import subprocess
import tempfile
import pytest

DEPS_PATH = "/home/user/deps.json"
CALCULATE_SCRIPT = "/home/user/calculate.sh"
WEIGHTS_JSON = "/home/user/weights.json"
ARTIFACT_S = "/home/user/artifact.s"
ARTIFACT_BIN = "/home/user/artifact"


def compute_expected_weights(deps_path):
    with open(deps_path, "r") as f:
        data = json.load(f)

    nodes = data["nodes"]
    edges = data["edges"]
    out_degree = {n: 0 for n in nodes}
    in_edges = {n: [] for n in nodes}

    for edge in edges:
        u = edge["from"]
        v = edge["to"]
        out_degree[u] += 1
        in_edges[v].append(u)

    weights = {n: 100 for n in nodes}
    for _ in range(3):
        new_weights = {}
        for n in nodes:
            w = 100
            for m in in_edges[n]:
                if out_degree[m] > 0:
                    w += weights[m] // out_degree[m]
            new_weights[n] = w
        weights = new_weights

    return weights


def winning_node(weights):
    return min(weights, key=lambda node: (-weights[node], node))


def run_calculate():
    if os.path.lexists(WEIGHTS_JSON):
        os.unlink(WEIGHTS_JSON)
    return subprocess.run(
        ["bash", CALCULATE_SCRIPT],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )


def load_student_weights():
    assert os.path.exists(WEIGHTS_JSON), f"Missing weights file: {WEIGHTS_JSON}"
    with open(WEIGHTS_JSON, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {WEIGHTS_JSON} is not valid JSON")


def test_calculate_script_exists():
    assert os.path.exists(CALCULATE_SCRIPT), f"Missing script: {CALCULATE_SCRIPT}"
    assert os.path.isfile(CALCULATE_SCRIPT), f"Not a file: {CALCULATE_SCRIPT}"


def test_weights_json_correct():
    result = run_calculate()
    assert result.returncode == 0, (
        f"{CALCULATE_SCRIPT} failed with exit code {result.returncode}: {result.stderr}"
    )

    student_weights = load_student_weights()
    expected_weights = compute_expected_weights(DEPS_PATH)
    expected_weights_str = {str(k): v for k, v in expected_weights.items()}
    assert student_weights == expected_weights_str, (
        f"Weights do not match expected values. Expected: {expected_weights_str}, "
        f"Got: {student_weights}"
    )


def test_calculate_reads_dependency_graph():
    with open(DEPS_PATH, "rb") as f:
        original_deps = f.read()

    alternate_deps = {
        "nodes": [2, 7, 11, 19],
        "edges": [
            {"from": 2, "to": 7},
            {"from": 2, "to": 11},
            {"from": 7, "to": 11},
            {"from": 11, "to": 2},
        ],
    }

    try:
        with open(DEPS_PATH, "w") as f:
            json.dump(alternate_deps, f)

        result = run_calculate()
        assert result.returncode == 0, (
            f"{CALCULATE_SCRIPT} failed on a dependency graph: {result.stderr}"
        )
        expected = compute_expected_weights(DEPS_PATH)
        expected_str = {str(k): v for k, v in expected.items()}
        assert load_student_weights() == expected_str
    finally:
        with open(DEPS_PATH, "wb") as f:
            f.write(original_deps)
        restore_result = run_calculate()
        assert restore_result.returncode == 0, (
            f"Failed to regenerate weights for the original graph: {restore_result.stderr}"
        )


def test_artifact_source_exists_and_builds():
    assert os.path.exists(ARTIFACT_S), f"Missing assembly file: {ARTIFACT_S}"
    assert os.path.isfile(ARTIFACT_S), f"Not a file: {ARTIFACT_S}"

    expected_weights = compute_expected_weights(DEPS_PATH)
    expected_winner = winning_node(expected_weights)

    with tempfile.TemporaryDirectory() as td:
        obj = os.path.join(td, "artifact.o")
        binary = os.path.join(td, "artifact")

        assembled = subprocess.run(
            ["nasm", "-f", "elf64", ARTIFACT_S, "-o", obj],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=15,
        )
        assert assembled.returncode == 0, f"nasm failed: {assembled.stderr}"

        linked = subprocess.run(
            ["ld", "-o", binary, obj],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=15,
        )
        assert linked.returncode == 0, f"ld failed: {linked.stderr}"

        result = subprocess.run([binary], timeout=10)
        assert result.returncode == expected_winner, (
            f"Executable rebuilt from {ARTIFACT_S} returned {result.returncode}; "
            f"expected {expected_winner}"
        )


def test_artifact_executable_exists_and_runs():
    assert os.path.exists(ARTIFACT_BIN), f"Missing executable: {ARTIFACT_BIN}"
    assert os.path.isfile(ARTIFACT_BIN), f"Not a file: {ARTIFACT_BIN}"

    st = os.stat(ARTIFACT_BIN)
    assert bool(st.st_mode & stat.S_IXUSR), f"File {ARTIFACT_BIN} is not executable"

    with open(ARTIFACT_BIN, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{ARTIFACT_BIN} is not an ELF executable"

    header = subprocess.run(
        ["readelf", "-h", ARTIFACT_BIN],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert header.returncode == 0, f"Invalid ELF executable: {header.stderr}"
    assert "ELF64" in header.stdout and "X86-64" in header.stdout, (
        f"{ARTIFACT_BIN} is not an x86_64 ELF executable"
    )

    expected_weights = compute_expected_weights(DEPS_PATH)
    expected_winner = winning_node(expected_weights)
    result = subprocess.run([ARTIFACT_BIN], timeout=10)
    assert result.returncode == expected_winner, (
        f"Expected exit code {expected_winner}, but got {result.returncode}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
