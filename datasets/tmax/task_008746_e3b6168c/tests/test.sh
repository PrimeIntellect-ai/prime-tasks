#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import math

PDB_PATH = "/home/user/input.pdb"


def parse_ca_atoms(path):
    atoms = []
    with open(path, "r") as handle:
        for line in handle:
            if line[0:6] not in ("ATOM  ", "HETATM"):
                continue
            if line[12:16].strip() != "CA":
                continue
            try:
                z = float(line[46:54])
                b_factor = float(line[60:66])
            except ValueError as exc:
                raise AssertionError(f"Invalid coordinate or B-factor in CA record: {line!r}") from exc
            assert math.isfinite(z) and math.isfinite(b_factor), "CA values must be finite"
            atoms.append((z, b_factor))
    assert atoms, f"No CA atoms found in {path}"
    return atoms


def wasserstein_1d(first, second):
    assert first and second, "Wasserstein distributions must be non-empty"
    first = sorted(first)
    second = sorted(second)
    i = j = 0
    previous = min(first[0], second[0])
    distance = 0.0

    while i < len(first) or j < len(second):
        next_first = first[i] if i < len(first) else math.inf
        next_second = second[j] if j < len(second) else math.inf
        current = min(next_first, next_second)
        distance += abs(i / len(first) - j / len(second)) * (current - previous)
        while i < len(first) and first[i] == current:
            i += 1
        while j < len(second) and second[j] == current:
            j += 1
        previous = current

    return distance


def compute_expected_results(path):
    atoms = parse_ca_atoms(path)
    z_min = min(z for z, _ in atoms)
    z_max = max(z for z, _ in atoms)
    assert z_max > z_min, "The CA atoms must span a non-zero Z-coordinate range"

    width = (z_max - z_min) / 5.0
    segments = [[] for _ in range(5)]
    boundaries = [z_min + width * index for index in range(1, 5)]

    for z, b_factor in atoms:
        if z == z_max:
            segment_index = 4
        else:
            # Counting boundaries strictly below z assigns exact boundary values
            # to the lower-index segment.
            segment_index = sum(z > boundary for boundary in boundaries)
        segments[segment_index].append(b_factor)

    assert all(segments), "Each of the five segments must contain at least one CA atom"

    distance = wasserstein_1d(segments[0], segments[4])
    means = [sum(values) / len(values) for values in segments]
    x_values = range(5)
    x_mean = 2.0
    y_mean = sum(means) / 5.0
    slope = sum((x - x_mean) * (y - y_mean) for x, y in zip(x_values, means)) / sum(
        (x - x_mean) ** 2 for x in x_values
    )
    return round(distance, 4), round(slope, 4)


def test_virtual_environment_exists():
    """Check if the Python virtual environment was created at the specified path."""
    venv_dir = "/home/user/analysis_env"
    assert os.path.isdir(venv_dir), f"Virtual environment directory not found at {venv_dir}"

    python_bin = os.path.join(venv_dir, "bin", "python")
    python3_bin = os.path.join(venv_dir, "bin", "python3")
    assert os.path.isfile(python_bin) or os.path.isfile(python3_bin), \
        f"Python executable not found in {os.path.join(venv_dir, 'bin')}. Ensure the virtual environment is correctly created."


def test_results_json_exists_and_correct():
    """Check results.json against values independently recomputed from input.pdb."""
    results_path = "/home/user/results.json"
    assert os.path.isfile(results_path), f"Results file missing at {results_path}"

    with open(results_path, "r") as handle:
        try:
            data = json.load(handle)
        except json.JSONDecodeError:
            assert False, f"The file {results_path} does not contain valid JSON."

    assert "wasserstein_distance" in data, "Key 'wasserstein_distance' is missing in results.json"
    assert "regression_slope" in data, "Key 'regression_slope' is missing in results.json"

    w_dist = data["wasserstein_distance"]
    r_slope = data["regression_slope"]
    assert isinstance(w_dist, (int, float)), f"'wasserstein_distance' must be a number, got {type(w_dist).__name__}"
    assert isinstance(r_slope, (int, float)), f"'regression_slope' must be a number, got {type(r_slope).__name__}"

    # Preserve the original assertions for this supplied structure.
    expected_w_dist = 20.0
    expected_r_slope = 5.0
    assert math.isclose(w_dist, expected_w_dist, rel_tol=1e-3, abs_tol=1e-3), \
        f"Expected 'wasserstein_distance' to be approximately {expected_w_dist}, but got {w_dist}"
    assert math.isclose(r_slope, expected_r_slope, rel_tol=1e-3, abs_tol=1e-3), \
        f"Expected 'regression_slope' to be approximately {expected_r_slope}, but got {r_slope}"

    # Independently parse the PDB, apply the specified boundary rule, and
    # recompute both statistics rather than trusting hardcoded answers alone.
    computed_w_dist, computed_r_slope = compute_expected_results(PDB_PATH)
    assert math.isclose(w_dist, computed_w_dist, rel_tol=0.0, abs_tol=5e-5), \
        f"Computed Wasserstein distance is {computed_w_dist:.4f}, but got {w_dist}"
    assert math.isclose(r_slope, computed_r_slope, rel_tol=0.0, abs_tol=5e-5), \
        f"Computed regression slope is {computed_r_slope:.4f}, but got {r_slope}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
