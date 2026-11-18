#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import pstats
import random
import subprocess
import urllib.request

import numpy as np
import pytest
import scipy.stats

SCRIPT = "/home/user/analyze_protein.py"
PDB = "/home/user/1CRN.pdb"
RESULTS = "/home/user/results.json"
PLOT = "/home/user/spectrum.png"
PROFILE = "/home/user/profile.txt"


def calculate_metrics(lines):
    coords = []
    for line in lines:
        if line.startswith("ATOM") and line[12:16].strip() == "CA":
            coords.append([
                float(line[30:38]),
                float(line[38:46]),
                float(line[46:54]),
            ])

    coords = np.asarray(coords, dtype=float)
    n = len(coords)
    degrees = np.zeros(n, dtype=int)
    edges = 0
    for i in range(n):
        for j in range(i + 1, n):
            if np.linalg.norm(coords[i] - coords[j]) < 8.0:
                edges += 1
                degrees[i] += 1
                degrees[j] += 1

    mag_positive = np.abs(np.fft.fft(degrees))[1:n // 2]
    peak_freq_index = int(np.argmax(mag_positive))

    np.random.seed(42)
    null_mags = []
    for _ in range(100):
        shuffled = np.random.permutation(degrees)
        null_mags.append(np.abs(np.fft.fft(shuffled))[1:n // 2])
    mean_null_mag = np.mean(null_mags, axis=0)
    _, p_value = scipy.stats.ttest_rel(mag_positive, mean_null_mag)

    return {
        "num_ca_atoms": n,
        "num_edges": edges,
        "peak_freq_index": peak_freq_index,
        "p_value": float(p_value),
    }


def get_expected_values():
    try:
        with urllib.request.urlopen(
            "https://files.rcsb.org/download/1CRN.pdb", timeout=30
        ) as response:
            lines = response.read().decode("utf-8").splitlines()
    except Exception as exc:
        pytest.fail(f"Failed to download the independent 1CRN reference: {exc}")
    return calculate_metrics(lines)


def run_submission():
    env = os.environ.copy()
    env["MPLBACKEND"] = "Agg"
    try:
        result = subprocess.run(
            ["python3", SCRIPT],
            cwd="/home/user",
            env=env,
            capture_output=True,
            text=True,
            timeout=180,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("analyze_protein.py timed out")
    assert result.returncode == 0, (
        "analyze_protein.py failed when executed.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def load_results():
    assert os.path.isfile(RESULTS), f"{RESULTS} is missing."
    try:
        with open(RESULTS, "r") as handle:
            return json.load(handle)
    except json.JSONDecodeError:
        pytest.fail(f"{RESULTS} does not contain valid JSON.")


def assert_metrics(results, expected):
    assert "num_ca_atoms" in results, "Key 'num_ca_atoms' missing in results.json"
    assert results["num_ca_atoms"] == expected["num_ca_atoms"], (
        f"Expected num_ca_atoms to be {expected['num_ca_atoms']}, "
        f"got {results['num_ca_atoms']}"
    )

    assert "num_edges" in results, "Key 'num_edges' missing in results.json"
    assert results["num_edges"] == expected["num_edges"], (
        f"Expected num_edges to be {expected['num_edges']}, "
        f"got {results['num_edges']}"
    )

    assert "peak_freq_index" in results, "Key 'peak_freq_index' missing in results.json"
    assert results["peak_freq_index"] == expected["peak_freq_index"], (
        f"Expected peak_freq_index to be {expected['peak_freq_index']}, "
        f"got {results['peak_freq_index']}"
    )

    assert "p_value" in results, "Key 'p_value' missing in results.json"
    assert math.isclose(results["p_value"], expected["p_value"], abs_tol=1e-4), (
        f"Expected p_value to be close to {expected['p_value']}, "
        f"got {results['p_value']}"
    )


def assert_profile_is_real():
    assert os.path.isfile(PROFILE), f"{PROFILE} is missing."
    assert os.path.getsize(PROFILE) > 0, (
        f"{PROFILE} is empty. Profiling may not have executed."
    )

    profiled_functions = []
    try:
        stats = pstats.Stats(PROFILE)
        profiled_functions = [
            (filename, function)
            for filename, _line, function in stats.stats
        ]
    except Exception:
        with open(PROFILE, "rb") as handle:
            text = handle.read().decode("utf-8", errors="ignore").lower()
        assert "function calls" in text, "profile.txt is not recognizable cProfile output"
        assert "analyze_protein.py" in text and "main" in text, (
            "profile.txt does not show analyze_protein.py's main function being profiled"
        )
    else:
        assert any(
            os.path.basename(filename) == "analyze_protein.py" and function == "main"
            for filename, function in profiled_functions
        ), "The cProfile data does not contain analyze_protein.py's main function"


def assert_plot_is_real():
    assert os.path.isfile(PLOT), f"{PLOT} is missing."
    assert os.path.getsize(PLOT) > 0, f"{PLOT} is empty."
    with open(PLOT, "rb") as handle:
        assert handle.read(8) == b"\x89PNG\r\n\x1a\n", "spectrum.png is not a PNG file"
    import matplotlib.image as mpimg
    image = mpimg.imread(PLOT)
    assert image.ndim in (2, 3) and image.shape[0] > 1 and image.shape[1] > 1
    assert float(np.max(image) - np.min(image)) > 0.01, "spectrum.png has no visible content"


@pytest.fixture(scope="module")
def expected_data():
    return get_expected_values()


def test_script_exists():
    assert os.path.isfile(SCRIPT), "/home/user/analyze_protein.py is missing."


def test_script_executes_and_generates_outputs():
    for path in (PDB, RESULTS, PLOT, PROFILE):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass
    run_submission()


def test_pdb_downloaded():
    assert os.path.isfile(PDB), "/home/user/1CRN.pdb is missing. The script should download it."
    assert os.path.getsize(PDB) > 0, "/home/user/1CRN.pdb is empty."


def test_spectrum_plot_exists():
    assert_plot_is_real()


def test_profile_exists():
    assert_profile_is_real()


def test_results_json(expected_data):
    assert_metrics(load_results(), expected_data)


def make_unknown_pdb():
    rng = random.SystemRandom()
    for _ in range(100):
        coords = [
            (rng.uniform(-3, 18), rng.uniform(-3, 18), rng.uniform(-3, 18))
            for _ in range(18)
        ]
        lines = []
        serial = 1
        for residue, (x, y, z) in enumerate(coords, 1):
            lines.append(
                f"ATOM  {serial:5d}  CA  ALA A{residue:4d}    "
                f"{x:8.3f}{y:8.3f}{z:8.3f}  1.00 20.00           C"
            )
            serial += 1
            # A non-CA atom ensures the parser does not count every ATOM record.
            lines.append(
                f"ATOM  {serial:5d}  CB  ALA A{residue:4d}    "
                f"{x + 0.7:8.3f}{y:8.3f}{z:8.3f}  1.00 20.00           C"
            )
            serial += 1
        expected = calculate_metrics(lines)
        if (
            0 < expected["num_edges"] < 153
            and math.isfinite(expected["p_value"])
        ):
            return lines, expected
    pytest.fail("Could not construct a suitable dynamic PDB test case")


def test_pipeline_on_unseen_existing_pdb():
    # The instruction says an already-existing PDB is reused. Supplying a fresh,
    # unpredictable structure proves the submitted script parses and analyzes it
    # rather than merely emitting hard-coded 1CRN answers.
    lines, expected = make_unknown_pdb()
    with open(PDB, "w") as handle:
        handle.write("\n".join(lines) + "\nEND\n")

    for path in (RESULTS, PLOT, PROFILE):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    run_submission()
    assert_metrics(load_results(), expected)
    assert_plot_is_real()
    assert_profile_is_real()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
