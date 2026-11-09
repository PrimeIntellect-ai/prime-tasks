#!/bin/bash
set -u
mkdir -p /logs/verifier

if (
set -e

cat << 'PY_EOF' > /tmp/preflight.py
import json
import math
import os
import shutil
import subprocess
import uuid

import numpy as np

FASTA = "/home/user/data/input.fasta"
MATRICES = "/home/user/data/matrices.json"
NOTEBOOK = "/home/user/analysis.ipynb"
RESULTS = "/home/user/results.json"
EXTRACTOR = "/tmp/extract_matrices_verifier"


def expected_matrices(records):
    order = "ACGT"
    index = {base: i for i, base in enumerate(order)}
    answer = {}
    for name, sequence in records.items():
        counts = [[0 for _ in range(4)] for _ in range(4)]
        for left, right in zip(sequence, sequence[1:]):
            counts[index[left]][index[right]] += 1
        matrix = []
        for row in counts:
            total = sum(row)
            matrix.append([value / total for value in row] if total else [0.0] * 4)
        answer[name] = matrix
    return answer


def assert_matrices(actual, expected):
    assert set(actual) == set(expected), (set(actual), set(expected))
    for name in expected:
        assert isinstance(actual[name], list) and len(actual[name]) == 4
        for got_row, wanted_row in zip(actual[name], expected[name]):
            assert isinstance(got_row, list) and len(got_row) == 4
            for got, wanted in zip(got_row, wanted_row):
                assert isinstance(got, (int, float)) and not isinstance(got, bool)
                assert math.isfinite(float(got))
                assert abs(float(got) - wanted) <= 1e-9, (name, actual[name], expected[name])


def execute_notebook():
    if os.path.exists(RESULTS):
        os.remove(RESULTS)
    subprocess.run(
        ["jupyter", "nbconvert", "--to", "notebook", "--execute", "--inplace",
         "--ExecutePreprocessor.timeout=300", NOTEBOOK],
        cwd="/home/user",
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=360,
    )
    assert os.path.isfile(RESULTS), "Notebook execution did not recreate results.json"


def posterior_stats(matrix):
    m = np.asarray(matrix, dtype=float)
    precision = m.T @ m + 0.1 * np.eye(4)
    covariance = np.linalg.inv(precision)
    mean = covariance @ m.T @ np.ones(4)
    expected_ci_width = 2.0 * 1.96 * math.sqrt(float(covariance[0, 0]) / 8000.0)
    return float(mean[0]), expected_ci_width


def assert_results_for(matrices):
    with open(RESULTS) as handle:
        results = json.load(handle)
    assert set(results) == set(matrices), (set(results), set(matrices))
    for name, matrix in matrices.items():
        item = results[name]
        assert isinstance(item, dict)
        assert set(["mean", "ci_lower", "ci_upper"]).issubset(item)
        values = [item["mean"], item["ci_lower"], item["ci_upper"]]
        assert all(isinstance(x, (int, float)) and not isinstance(x, bool) for x in values)
        assert all(math.isfinite(float(x)) for x in values)
        mean, lower, upper = map(float, values)
        assert lower < mean < upper, (name, lower, mean, upper)
        wanted_mean, wanted_width = posterior_stats(matrix)
        assert abs(mean - wanted_mean) <= 0.10, (name, mean, wanted_mean)
        width = upper - lower
        assert 0.20 * wanted_width <= width <= 5.0 * wanted_width, (name, width, wanted_width)


# The submitted source must really compile.
subprocess.run(
    ["g++", "-std=c++17", "-O2", "/home/user/src/extract_matrices.cpp", "-o", EXTRACTOR],
    check=True,
)

# Exercise the extractor on unpredictable IDs and content, then restore the supplied FASTA.
with open(FASTA, "rb") as handle:
    original_fasta = handle.read()
try:
    token = uuid.uuid4().hex
    records = {
        "Verifier_" + token[:12]: "AAAACCCCGGGGTTTTACGA",
        "Degenerate_" + token[12:24]: "TTTTTTTTTTTT",
        "Mixed_" + token[24:]: "AGCTTAGGCTAATCGC",
    }
    with open(FASTA, "w") as handle:
        for name, sequence in records.items():
            handle.write(f">{name}\n{sequence}\n")
    if os.path.exists(MATRICES):
        os.remove(MATRICES)
    subprocess.run([EXTRACTOR], check=True, cwd="/home/user")
    with open(MATRICES) as handle:
        assert_matrices(json.load(handle), expected_matrices(records))
finally:
    with open(FASTA, "wb") as handle:
        handle.write(original_fasta)

# Regenerate matrices for the real input using the submitted executable.
if os.path.exists(MATRICES):
    os.remove(MATRICES)
subprocess.run([EXTRACTOR], check=True, cwd="/home/user")
assert os.path.isfile(MATRICES), "Extractor did not recreate matrices.json"
with open(MATRICES, "rb") as handle:
    original_matrices_bytes = handle.read()

# Check that the notebook contains the requested workflow rather than only constants.
with open(NOTEBOOK) as handle:
    notebook = json.load(handle)
assert notebook.get("nbformat") == 4
cells = notebook.get("cells", [])
assert cells and cells[-1].get("cell_type") == "code", "The final notebook cell must be code"
source = "\n".join("".join(cell.get("source", [])) for cell in cells if cell.get("cell_type") == "code")
normalized = source.lower().replace("_", "")
assert ("emcee" in normalized or "metropolis" in normalized), "No MCMC sampler implementation found"
assert "bootstrap" in normalized, "No bootstrap implementation found"
for required in ("10000", "2000", "1000"):
    assert required in normalized, f"Notebook does not specify required count {required}"
assert "results.json" in "".join(cells[-1].get("source", [])).lower(), "Final cell does not write results.json"

# Run the notebook against verifier-selected matrices so fixed Seq1/Seq2/Seq3 results fail.
challenge = {
    "Challenge_" + uuid.uuid4().hex[:10]: [
        [1.0, 0.0, 0.0, 0.0],
        [1.0, 0.0, 0.0, 0.0],
        [1.0, 0.0, 0.0, 0.0],
        [1.0, 0.0, 0.0, 0.0],
    ],
    "Zero_" + uuid.uuid4().hex[:10]: [[0.0, 0.0, 0.0, 0.0] for _ in range(4)],
}
try:
    with open(MATRICES, "w") as handle:
        json.dump(challenge, handle)
    execute_notebook()
    assert_results_for(challenge)
finally:
    with open(MATRICES, "wb") as handle:
        handle.write(original_matrices_bytes)
    # Leave the requested final artifacts regenerated for the supplied input.
    execute_notebook()
PY_EOF

python3 /tmp/preflight.py

cat << 'PYTEST_EOF' > /tmp/test_final_state.py
import json
import math
import os

import numpy as np
import pytest


def parse_fasta(path):
    records = {}
    current = None
    with open(path) as handle:
        for raw in handle:
            line = raw.strip()
            if not line:
                continue
            if line.startswith(">"):
                current = line[1:].split()[0]
                records[current] = ""
            else:
                assert current is not None
                records[current] += line.upper()
    return records


def derive_matrix(sequence):
    index = {base: i for i, base in enumerate("ACGT")}
    counts = [[0] * 4 for _ in range(4)]
    for left, right in zip(sequence, sequence[1:]):
        counts[index[left]][index[right]] += 1
    result = []
    for row in counts:
        total = sum(row)
        result.append([x / total for x in row] if total else [0.0] * 4)
    return result


def test_files_exist():
    """Verify that all expected output files exist."""
    expected_files = [
        "/home/user/src/extract_matrices.cpp",
        "/home/user/data/matrices.json",
        "/home/user/analysis.ipynb",
        "/home/user/results.json"
    ]
    for path in expected_files:
        assert os.path.isfile(path), f"Expected file {path} is missing."


def test_matrices_json_structure():
    """Verify the original structure checks and the actual FASTA-derived probabilities."""
    path = "/home/user/data/matrices.json"
    with open(path, "r") as f:
        try:
            matrices = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{path} is not a valid JSON file.")

    expected_keys = {"Seq1", "Seq2", "Seq3"}
    assert set(matrices.keys()) == expected_keys, f"{path} keys do not match expected sequences."

    records = parse_fasta("/home/user/data/input.fasta")
    for seq, matrix in matrices.items():
        assert isinstance(matrix, list), f"Matrix for {seq} is not a list."
        assert len(matrix) == 4, f"Matrix for {seq} does not have 4 rows."
        wanted = derive_matrix(records[seq])
        for row_index, row in enumerate(matrix):
            assert isinstance(row, list), f"Row in {seq} matrix is not a list."
            assert len(row) == 4, f"Row in {seq} matrix does not have 4 columns."
            for column, value in enumerate(row):
                assert isinstance(value, (int, float)) and not isinstance(value, bool)
                assert math.isfinite(float(value))
                assert abs(float(value) - wanted[row_index][column]) <= 1e-9


def test_results_json_content():
    """Verify original checks plus posterior and bootstrap consistency."""
    path = "/home/user/results.json"
    with open(path, "r") as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{path} is not a valid JSON file.")

    expected_keys = {"Seq1", "Seq2", "Seq3"}
    assert set(results.keys()) == expected_keys, f"{path} keys do not match expected sequences."

    expected_means = {
        "Seq1": 0.909,
        "Seq2": 0.909,
        "Seq3": 0.0
    }
    tolerance = 0.05
    with open("/home/user/data/matrices.json") as handle:
        matrices = json.load(handle)

    for seq, data in results.items():
        for key in ["mean", "ci_lower", "ci_upper"]:
            assert key in data, f"Missing key '{key}' in {seq} results."
            assert isinstance(data[key], (int, float)), f"Value for '{key}' in {seq} is not numeric."
            assert not isinstance(data[key], bool)
            assert math.isfinite(float(data[key]))

        mean = float(data["mean"])
        ci_lower = float(data["ci_lower"])
        ci_upper = float(data["ci_upper"])

        # Preserve the original CI and fixed-input mean assertions.
        assert ci_lower <= mean <= ci_upper, f"Confidence interval for {seq} is invalid: {ci_lower} <= {mean} <= {ci_upper} is False."
        expected_mean = expected_means[seq]
        assert abs(mean - expected_mean) <= tolerance, f"Mean for {seq} ({mean}) is not within {tolerance} of expected ({expected_mean})."

        m = np.asarray(matrices[seq], dtype=float)
        covariance = np.linalg.inv(m.T @ m + 0.1 * np.eye(4))
        posterior_mean = covariance @ m.T @ np.ones(4)
        assert abs(mean - float(posterior_mean[0])) <= 0.05
        expected_width = 2.0 * 1.96 * math.sqrt(float(covariance[0, 0]) / 8000.0)
        actual_width = ci_upper - ci_lower
        assert ci_lower < ci_upper
        assert 0.20 * expected_width <= actual_width <= 5.0 * expected_width


def test_notebook_was_fully_executed():
    with open("/home/user/analysis.ipynb") as handle:
        notebook = json.load(handle)
    code_cells = [c for c in notebook.get("cells", []) if c.get("cell_type") == "code" and "".join(c.get("source", [])).strip()]
    assert code_cells
    assert all(c.get("execution_count") is not None for c in code_cells), "Notebook contains unexecuted code cells"
PYTEST_EOF

python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short
); then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
