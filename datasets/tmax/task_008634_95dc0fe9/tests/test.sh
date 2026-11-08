#!/bin/bash
set -e
mkdir -p /logs/verifier
export RUSTUP_HOME=/opt/rust
export CARGO_HOME=/opt/cargo

backup="$(mktemp)"
cp /home/user/raw_molecules.h5 "$backup"

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import subprocess

import h5py
import numpy as np

PROJECT = "/home/user/graph_prep"
INPUT = "/home/user/raw_molecules.h5"
OUTPUT = "/home/user/features.jsonl"
REQUIRED_KEYS = {"graph_id", "a", "b", "c", "stable"}


def expected_features():
    expected = {}
    with h5py.File(INPUT, "r") as f:
        assert "graphs" in f, "Input is missing /graphs"
        for graph_id, dataset in f["graphs"].items():
            A = np.asarray(dataset[...], dtype=np.float64)
            assert A.ndim == 2 and A.shape[0] == A.shape[1]
            D = np.diag(A.sum(axis=1))
            eigenvalues = np.linalg.eigvalsh(D - A)
            eigenvalues.sort()
            x = np.arange(len(eigenvalues), dtype=np.float64)
            design = np.column_stack((x * x, x, np.ones_like(x)))
            a, b, c = np.linalg.lstsq(design, eigenvalues, rcond=None)[0]
            expected[graph_id] = {
                "a": float(a),
                "b": float(b),
                "c": float(c),
                "stable": bool(-1e-5 <= eigenvalues[0] <= 1e-5),
            }
    return expected


def run_project():
    assert os.path.isdir(PROJECT), f"Rust project missing: {PROJECT}"
    assert os.path.isfile(os.path.join(PROJECT, "Cargo.toml")), "Cargo.toml is missing"
    assert os.path.isfile(os.path.join(PROJECT, "src", "main.rs")), "src/main.rs is missing"
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    completed = subprocess.run(
        ["cargo", "run", "--quiet"],
        cwd=PROJECT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=600,
    )
    assert completed.returncode == 0, "cargo run failed:\n" + completed.stdout
    assert os.path.exists(OUTPUT), f"Output file missing: {OUTPUT}"
    assert os.path.isfile(OUTPUT), f"Path is not a file: {OUTPUT}"


def validate_output(expected):
    with open(OUTPUT, "r", encoding="utf-8") as f:
        lines = f.read().splitlines()
    assert lines, f"No JSON lines found in {OUTPUT}"
    assert all(line.strip() for line in lines), "Output contains a blank line"
    assert len(lines) == len(expected), (
        f"Expected {len(expected)} lines in {OUTPUT}, got {len(lines)}"
    )

    results = {}
    for line in lines:
        try:
            data = json.loads(line)
        except json.JSONDecodeError as exc:
            raise AssertionError(f"Invalid JSON line: {line}") from exc
        assert isinstance(data, dict), f"JSON line is not an object: {data!r}"
        assert set(data) == REQUIRED_KEYS, (
            f"Expected exactly keys {sorted(REQUIRED_KEYS)}, got {sorted(data)}"
        )
        assert isinstance(data["graph_id"], str), "graph_id must be a string"
        assert data["graph_id"] not in results, f"Duplicate graph_id: {data['graph_id']}"
        assert type(data["stable"]) is bool, "stable must be a boolean"
        for key in ("a", "b", "c"):
            assert isinstance(data[key], (int, float)) and not isinstance(data[key], bool), (
                f"{key} must be numeric"
            )
            assert math.isfinite(float(data[key])), f"{key} must be finite"
        results[data["graph_id"]] = data

    assert set(results) == set(expected), (
        f"Expected graph IDs {sorted(expected)}, got {sorted(results)}"
    )
    for graph_id, want in expected.items():
        got = results[graph_id]
        assert got["stable"] is want["stable"], (
            f"{graph_id} stable expected {want['stable']}, got {got['stable']}"
        )
        for key in ("a", "b", "c"):
            assert np.isclose(float(got[key]), want[key], rtol=1e-5, atol=1e-6), (
                f"{graph_id} {key} expected {want[key]}, got {got[key]}"
            )


def install_probe_input():
    graphs = {
        "graph_0": np.array([
            [0.0, 0.5, 0.0, 1.25],
            [0.5, 0.0, 2.0, 0.0],
            [0.0, 2.0, 0.0, 0.75],
            [1.25, 0.0, 0.75, 0.0],
        ]),
        "graph_1": np.array([
            [0.0, -1.5, 0.25],
            [-1.5, 0.0, 0.25],
            [0.25, 0.25, 0.0],
        ]),
        "graph_2": np.array([
            [0.0, 0.4, 0.0, 0.0, 1.1],
            [0.4, 0.0, 0.8, 0.0, 0.0],
            [0.0, 0.8, 0.0, 1.3, 0.2],
            [0.0, 0.0, 1.3, 0.0, 0.6],
            [1.1, 0.0, 0.2, 0.6, 0.0],
        ]),
    }
    with h5py.File(INPUT, "w") as f:
        group = f.create_group("graphs")
        for graph_id, adjacency in graphs.items():
            group.create_dataset(graph_id, data=adjacency.astype(np.float64))


def test_rust_pipeline_on_original_and_probe_inputs():
    # Preserve the original existence/content checks, with expectations derived
    # from the instructed Laplacian, eigenspectrum, and OLS definitions.
    original_expected = expected_features()
    assert len(original_expected) >= 2
    assert "graph_0" in original_expected
    assert "graph_1" in original_expected
    assert original_expected["graph_0"]["stable"] is True
    assert original_expected["graph_1"]["stable"] is False
    run_project()
    validate_output(original_expected)

    # A second unseen HDF5 input ensures the executable reads and computes from
    # the input rather than merely emitting the two known answers.
    install_probe_input()
    probe_expected = expected_features()
    run_project()
    validate_output(probe_expected)
TEST_EOF

set +e
python3 -m pytest /tmp/test_final_state.py -x --tb=short
status=$?

# Restore the instructed input regardless of the test outcome.
cp "$backup" /home/user/raw_molecules.h5
rm -f "$backup"

# Leave features.jsonl fully generated for the original input.
if [ "$status" -eq 0 ]; then
    rm -f /home/user/features.jsonl
    (cd /home/user/graph_prep && timeout 600 cargo run --quiet)
    status=$?
fi

if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
