#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import re
import subprocess
import tempfile

import pytest

HOME = "/home/user"
SOURCE = f"{HOME}/diffusion.c"
EXECUTABLE = f"{HOME}/diffusion_sim"
GRAPH = f"{HOME}/molecule_graph.txt"
RESULTS = f"{HOME}/sim_results.csv"
REFERENCE = f"{HOME}/reference_data.csv"
REPORT = f"{HOME}/report.txt"


def read_graph(path):
    with open(path, "r") as f:
        values = f.read().split()
    assert len(values) >= 2, "Graph file is malformed"
    n, edge_count = map(int, values[:2])
    assert len(values) == 2 + 2 * edge_count, "Graph edge count is malformed"
    adjacency = [[0.0] * n for _ in range(n)]
    pos = 2
    for _ in range(edge_count):
        u, v = map(int, values[pos:pos + 2])
        pos += 2
        assert 0 <= u < n and 0 <= v < n, "Graph contains an invalid node"
        adjacency[u][v] = 1.0
        adjacency[v][u] = 1.0
    return adjacency


def expected_simulation(graph_path):
    adjacency = read_graph(graph_path)
    n = len(adjacency)
    x = [10.0 if i == 0 else 0.0 for i in range(n)]
    t = 0.0
    dt = 0.01
    rows = []
    while t <= 6.0:
        energy = sum(value * value for value in x)
        rows.append((float(f"{t:.4f}"), float(f"{energy:.6f}")))
        dx = [0.0] * n
        for i in range(n):
            for j in range(n):
                if adjacency[i][j] > 0.0:
                    dx[i] += -(x[i] - x[j])
        for i in range(n):
            x[i] += dx[i] * dt
        t += dt
    return rows


def read_results(path):
    assert os.path.isfile(path), f"Missing simulation results: {path}"
    with open(path, "r", newline="") as f:
        reader = csv.reader(f)
        rows = list(reader)
    assert len(rows) > 10, "sim_results.csv seems to have too few lines."
    assert rows[0] == ["Time", "SystemEnergy"], "Header missing or incorrect in sim_results.csv"
    parsed = []
    for line_number, row in enumerate(rows[1:], 2):
        assert len(row) == 2, f"CSV row {line_number} does not have two columns"
        try:
            t = float(row[0])
            energy = float(row[1])
        except ValueError:
            pytest.fail(f"CSV row {line_number} contains a non-numeric value")
        assert math.isfinite(t) and math.isfinite(energy), f"CSV row {line_number} contains NaN or Inf"
        assert energy > 0.0, f"CSV row {line_number} has non-positive energy"
        parsed.append((t, energy))
    return parsed


def assert_expected_results(actual_path, graph_path):
    actual = read_results(actual_path)
    expected = expected_simulation(graph_path)
    assert len(actual) == len(expected), f"Expected {len(expected)} data rows, got {len(actual)}"
    for index, ((actual_t, actual_e), (expected_t, expected_e)) in enumerate(zip(actual, expected), 2):
        assert math.isclose(actual_t, expected_t, rel_tol=0.0, abs_tol=5e-5), \
            f"Incorrect time at CSV row {index}: expected {expected_t}, got {actual_t}"
        assert math.isclose(actual_e, expected_e, rel_tol=0.0, abs_tol=1.1e-6), \
            f"Incorrect energy at CSV row {index}: expected {expected_e}, got {actual_e}"
    return actual


def run_program(executable, graph_path, output_path):
    completed = subprocess.run(
        [executable, graph_path, output_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert completed.returncode == 0, (
        f"{executable} failed with exit code {completed.returncode}: {completed.stderr}"
    )
    assert os.path.isfile(output_path), "Simulation did not create its requested output file"


def ols_alpha(rows):
    selected = [(t, math.log(energy)) for t, energy in rows if 1.0 <= t <= 5.0]
    assert len(selected) >= 2, "Not enough simulation points in the inclusive interval [1.0, 5.0]"
    n = len(selected)
    sum_x = sum(t for t, _ in selected)
    sum_y = sum(y for _, y in selected)
    sum_xy = sum(t * y for t, y in selected)
    sum_x2 = sum(t * t for t, _ in selected)
    denominator = n * sum_x2 - sum_x * sum_x
    assert denominator != 0.0, "Regression denominator is zero"
    slope = (n * sum_xy - sum_x * sum_y) / denominator
    return -slope


def mol_beta_reference():
    with open(REFERENCE, "r", newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            if row.get("Molecule") == "Mol_Beta":
                return float(row["Alpha_Theoretical"])
    pytest.fail("Mol_Beta is missing from reference_data.csv")


def test_executable_exists_and_is_compiled_binary():
    assert os.path.isfile(EXECUTABLE), f"Missing executable: {EXECUTABLE}"
    assert os.access(EXECUTABLE, os.X_OK), f"File is not executable: {EXECUTABLE}"
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "diffusion_sim is not a compiled ELF executable"


def test_diffusion_c_fixed():
    assert os.path.isfile(SOURCE), f"Missing file: {SOURCE}"
    with open(SOURCE, "r") as f:
        content = f.read()
    assert "dt = dt * 1.5;" not in content, \
        "The buggy adaptive step size logic 'dt = dt * 1.5;' was not removed from diffusion.c"
    assert re.search(r"\bdouble\s+dt\s*=\s*0\.01\s*;", content), \
        "diffusion.c does not initialize the constant step size to dt = 0.01"


def test_submitted_results_and_executable_behavior():
    # Validate the required saved run independently.
    assert_expected_results(RESULTS, GRAPH)

    # Actually execute the submitted artifact on the required graph.
    with tempfile.TemporaryDirectory() as directory:
        fresh_output = os.path.join(directory, "fresh.csv")
        run_program(EXECUTABLE, GRAPH, fresh_output)
        assert_expected_results(fresh_output, GRAPH)

        # Exercise it on an additional graph so a canned CSV-producing executable cannot pass.
        private_graph = os.path.join(directory, "private_graph.txt")
        with open(private_graph, "w") as f:
            f.write("5 5\n0 1\n0 2\n1 3\n2 4\n3 4\n")
        private_output = os.path.join(directory, "private.csv")
        run_program(EXECUTABLE, private_graph, private_output)
        assert_expected_results(private_output, private_graph)


def test_source_compiles_and_has_correct_behavior():
    # Ensure the fixed source itself, rather than only a separately supplied binary, works.
    with tempfile.TemporaryDirectory() as directory:
        rebuilt = os.path.join(directory, "diffusion_rebuilt")
        completed = subprocess.run(
            ["gcc", SOURCE, "-lm", "-o", rebuilt],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=15,
        )
        assert completed.returncode == 0, f"diffusion.c does not compile: {completed.stderr}"
        output = os.path.join(directory, "rebuilt.csv")
        run_program(rebuilt, GRAPH, output)
        assert_expected_results(output, GRAPH)


def test_report_content_matches_regression():
    assert os.path.isfile(REPORT), f"Missing report file: {REPORT}"
    with open(REPORT, "r") as f:
        content = f.read()

    pattern = (
        r"\AComputed Alpha: ([0-9]+\.[0-9]{4})\n"
        r"Reference Alpha: ([0-9]+\.[0-9]{4})\n"
        r"Difference: ([0-9]+\.[0-9]{4})\n?\Z"
    )
    match = re.fullmatch(pattern, content)
    assert match is not None, "report.txt does not have the exact required three-line format with four decimal places"

    computed_alpha = float(match.group(1))
    reference_alpha = float(match.group(2))
    difference = float(match.group(3))

    expected_reference = mol_beta_reference()
    assert math.isclose(reference_alpha, 1.1716, rel_tol=0.0, abs_tol=0.0001), \
        f"Expected Reference Alpha to be 1.1716, got {reference_alpha}"
    assert math.isclose(reference_alpha, expected_reference, rel_tol=0.0, abs_tol=5e-5), \
        f"Reference Alpha does not match Mol_Beta in reference_data.csv"

    rows = read_results(RESULTS)
    expected_alpha = ols_alpha(rows)
    assert math.isclose(computed_alpha, expected_alpha, rel_tol=0.0, abs_tol=5e-5), \
        f"Computed Alpha is not the OLS result from sim_results.csv: expected {expected_alpha:.4f}, got {computed_alpha:.4f}"

    expected_diff = abs(computed_alpha - reference_alpha)
    assert math.isclose(difference, expected_diff, rel_tol=0.0, abs_tol=0.0002), \
        f"Difference is not calculated correctly. Expected {expected_diff}, got {difference}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
