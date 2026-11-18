#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import json
import math
import os
import subprocess
import sys

import numpy as np
import pytest
from scipy.stats import ks_2samp

RESULTS = "/home/user/results.json"
ANALYZE = "/home/user/analyze.py"
SPECTRO = "/home/user/sim/spectro_mc.py"
OBS = "/home/user/data/obs_raw.csv"


def load_results():
    with open(RESULTS, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {RESULTS} is not valid JSON.")


def run_analyze():
    if os.path.exists(RESULTS):
        os.unlink(RESULTS)
    completed = subprocess.run(
        [sys.executable, ANALYZE],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=180,
    )
    assert completed.returncode == 0, (
        f"analyze.py failed with exit code {completed.returncode}\n"
        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )
    assert os.path.isfile(RESULTS), "analyze.py did not create /home/user/results.json"
    return load_results()


def expected_simulation():
    energies = []
    for seed in range(42, 142):
        np.random.seed(seed)
        energies.extend(
            np.random.lognormal(mean=1.5, sigma=0.8, size=5000).tolist()
        )
    return energies


def assert_result_values(data, energies, observations):
    required_keys = ["total_simulated_energy", "ks_stat", "p_value"]
    for key in required_keys:
        assert key in data, f"Missing key '{key}' in {RESULTS}"
        assert isinstance(data[key], (int, float)) and not isinstance(data[key], bool), \
            f"Value for '{key}' must be numeric"

    ks = ks_2samp(observations, energies)
    expected = {
        "total_simulated_energy": round(math.fsum(energies), 6),
        "ks_stat": round(float(ks.statistic), 6),
        "p_value": round(float(ks.pvalue), 6),
    }
    assert data["total_simulated_energy"] == expected["total_simulated_energy"], \
        f"Incorrect total_simulated_energy: expected {expected['total_simulated_energy']}, got {data['total_simulated_energy']}"
    assert data["ks_stat"] == expected["ks_stat"], \
        f"Incorrect ks_stat: expected {expected['ks_stat']}, got {data['ks_stat']}"
    assert data["p_value"] == expected["p_value"], \
        f"Incorrect p_value: expected {expected['p_value']}, got {data['p_value']}"


def test_results_json_exists():
    assert os.path.isfile(RESULTS), f"Results file not found at {RESULTS}"


def test_results_json_content():
    data = load_results()

    required_keys = ["total_simulated_energy", "ks_stat", "p_value"]
    for key in required_keys:
        assert key in data, f"Missing key '{key}' in {RESULTS}"

    # Expected values derived from the deterministic numpy lognormal generation
    expected_energy = 3089450.418047
    expected_ks = 0.012540
    expected_p = 0.000000

    assert abs(data["total_simulated_energy"] - expected_energy) < 1e-5, \
        f"Incorrect total_simulated_energy: expected {expected_energy}, got {data['total_simulated_energy']}"
    assert abs(data["ks_stat"] - expected_ks) < 1e-5, \
        f"Incorrect ks_stat: expected {expected_ks}, got {data['ks_stat']}"
    assert abs(data["p_value"] - expected_p) < 1e-5, \
        f"Incorrect p_value: expected {expected_p}, got {data['p_value']}"


def test_analyze_script_exists():
    assert os.path.isfile(ANALYZE), f"Analysis script not found at {ANALYZE}"


def test_spectro_mc_fixed():
    assert os.path.isfile(SPECTRO), f"Simulation script not found at {SPECTRO}"

    with open(SPECTRO, "r") as f:
        content = f.read()

    assert "imap_unordered" not in content, \
        "The simulation script still contains 'imap_unordered', which causes non-deterministic ordering."
    assert "math.fsum" in content, \
        "The simulation script does not use 'math.fsum' to compute the total energy deterministically."


def test_simulation_behavior_and_determinism():
    expected = expected_simulation()
    expected_total = math.fsum(expected)

    spec = importlib.util.spec_from_file_location("submitted_spectro_mc", SPECTRO)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert callable(getattr(module, "run_simulation", None)), \
        "spectro_mc.py does not define a callable run_simulation"

    first = module.run_simulation()
    second = module.run_simulation()
    assert isinstance(first, tuple) and len(first) == 2, \
        "run_simulation must return (total_energy, all_energies)"
    assert isinstance(second, tuple) and len(second) == 2

    first_total, first_energies = first
    second_total, second_energies = second
    assert len(first_energies) == 500000, "Simulation returned the wrong number of energies"
    assert len(second_energies) == 500000, "Simulation returned the wrong number of energies"
    assert np.array_equal(np.asarray(first_energies), np.asarray(expected)), \
        "Simulated energies are not flattened in deterministic seed order or parameters/seeds were changed"
    assert np.array_equal(np.asarray(second_energies), np.asarray(expected)), \
        "Simulation output changed between runs"
    assert first_total == expected_total, \
        "Simulation total is not the math.fsum of the deterministically ordered flattened energies"
    assert second_total == expected_total, \
        "Simulation total changed between runs"


def test_analyze_executes_and_uses_supplied_observations():
    original_obs = open(OBS, "rb").read()
    rng = np.random.default_rng(int.from_bytes(os.urandom(16), "big"))
    observations = rng.lognormal(mean=2.15, sigma=0.37, size=137)

    try:
        with open(OBS, "w") as f:
            f.write("timestamp,detector_id,energy_kev\n")
            for i, value in enumerate(observations):
                f.write(f"1700000000,{i % 7},{value:.12f}\n")
        supplied_observations = np.asarray([float(f"{v:.12f}") for v in observations])
        data = run_analyze()
        assert_result_values(data, expected_simulation(), supplied_observations)
    finally:
        with open(OBS, "wb") as f:
            f.write(original_obs)

    # Re-run on the original input so the final artifact must also be generated by
    # the submitted script and retain the originally required values.
    data = run_analyze()
    expected_energy = 3089450.418047
    expected_ks = 0.012540
    expected_p = 0.000000
    assert abs(data["total_simulated_energy"] - expected_energy) < 1e-5
    assert abs(data["ks_stat"] - expected_ks) < 1e-5
    assert abs(data["p_value"] - expected_p) < 1e-5
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
