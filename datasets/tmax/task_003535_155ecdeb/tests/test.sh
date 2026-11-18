#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import contextlib
import csv
import io
import json
import math
import os
import random
import runpy
import sys

import numpy as np
from scipy.optimize import root_scalar

WORKSPACE = "/home/user/spectroscopy_ml"
GENERATOR = os.path.join(WORKSPACE, "generate_spectra.py")
BOOTSTRAP = os.path.join(WORKSPACE, "bootstrap_ci.py")
OBSERVATIONS = os.path.join(WORKSPACE, "observations.csv")
RESULTS = os.path.join(WORKSPACE, "results.json")


def load_results():
    with open(RESULTS, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            assert False, "results.json is not a valid JSON file."


def test_generate_spectra_uses_fsum():
    assert os.path.isfile(GENERATOR), f"Simulation script {GENERATOR} is missing."
    with open(GENERATOR, "r") as f:
        content = f.read()
    assert "math.fsum" in content, (
        "The script generate_spectra.py does not appear to use math.fsum() "
        "as required for numerical stability."
    )


def test_bootstrap_script_exists():
    assert os.path.isfile(BOOTSTRAP), f"Bootstrap script {BOOTSTRAP} is missing."


def test_results_json_exists_and_format():
    assert os.path.isfile(RESULTS), f"Results file {RESULTS} is missing."
    results = load_results()
    expected_keys = {"stable_energy", "bootstrap_ci_lower", "bootstrap_ci_upper"}
    assert set(results.keys()) == expected_keys, (
        f"results.json must contain exactly the keys {expected_keys}. "
        f"Found: {set(results.keys())}"
    )
    assert isinstance(results["stable_energy"], float), "stable_energy must be a float."
    assert isinstance(results["bootstrap_ci_lower"], float), "bootstrap_ci_lower must be a float."
    assert isinstance(results["bootstrap_ci_upper"], float), "bootstrap_ci_upper must be a float."


def reference_chunk(start_idx, end_idx):
    x = np.linspace(0, 10, 100000)[start_idx:end_idx]
    source = np.sin(x) ** 2 + 0.1 * x

    def nonlinear_response(intensity, source_val):
        return intensity ** 3 + 0.5 * intensity - source_val

    chunk_energy = 0.0
    for source_val in source:
        result = root_scalar(
            nonlinear_response, args=(source_val,), bracket=[0, 10]
        )
        chunk_energy += result.root
    return chunk_energy


def test_stable_energy_matches_script_output_and_real_fsum_reduction():
    results = load_results()

    chunks = [(i, i + 1000) for i in range(0, 100000, 1000)]
    random.seed(123)
    random.shuffle(chunks)
    expected_energies = [reference_chunk(start, end) for start, end in chunks]
    expected_energy = math.fsum(expected_energies)

    original_fsum = math.fsum
    observed_calls = []

    def recording_fsum(values):
        materialized = tuple(values)
        value = original_fsum(materialized)
        observed_calls.append((materialized, value))
        return value

    stdout = io.StringIO()
    old_argv = sys.argv[:]
    math.fsum = recording_fsum
    sys.argv = [GENERATOR]
    try:
        with contextlib.redirect_stdout(stdout):
            runpy.run_path(GENERATOR, run_name="__main__")
    except SystemExit as exc:
        assert exc.code in (None, 0), f"generate_spectra.py exited with status {exc.code}"
    finally:
        math.fsum = original_fsum
        sys.argv = old_argv

    matching_calls = []
    for values, returned_value in observed_calls:
        if len(values) == len(expected_energies) and np.allclose(
            np.asarray(values, dtype=float),
            np.asarray(expected_energies, dtype=float),
            rtol=0.0,
            atol=1e-12,
        ):
            matching_calls.append(returned_value)

    assert matching_calls, (
        "generate_spectra.py did not actually call math.fsum() on the computed "
        "domain-chunk energies."
    )

    energy_str = None
    for line in stdout.getvalue().splitlines():
        if "Total Integrated Energy:" in line:
            energy_str = line.split(":")[-1].strip()
            break
    assert energy_str is not None, "Could not find 'Total Integrated Energy:' in script output."
    try:
        script_energy = float(energy_str)
    except ValueError:
        assert False, f"Could not parse energy value from script output: {energy_str}"

    assert script_energy == expected_energy, (
        f"generate_spectra.py printed {script_energy}, but the stable reduction of "
        f"the independently computed chunk energies is {expected_energy}."
    )
    assert any(value == script_energy for value in matching_calls), (
        "The printed total energy was not the value returned by math.fsum()."
    )
    assert math.isclose(results["stable_energy"], script_energy, rel_tol=1e-12), (
        f"stable_energy in results.json ({results['stable_energy']}) does not match "
        f"the output of generate_spectra.py ({script_energy})."
    )


def test_bootstrap_ci_values():
    results = load_results()
    observations = []
    with open(OBSERVATIONS, "r") as f:
        reader = csv.DictReader(f)
        for row in reader:
            observations.append(float(row["intensity"]))

    np.random.seed(42)
    bootstrapped_means = []
    for _ in range(10000):
        sample = np.random.choice(observations, size=len(observations), replace=True)
        bootstrapped_means.append(np.mean(sample))

    expected_lower = float(round(np.percentile(bootstrapped_means, 2.5), 3))
    expected_upper = float(round(np.percentile(bootstrapped_means, 97.5), 3))

    assert math.isclose(results["bootstrap_ci_lower"], expected_lower, abs_tol=1e-3), (
        f"bootstrap_ci_lower is {results['bootstrap_ci_lower']}, expected {expected_lower}"
    )
    assert math.isclose(results["bootstrap_ci_upper"], expected_upper, abs_tol=1e-3), (
        f"bootstrap_ci_upper is {results['bootstrap_ci_upper']}, expected {expected_upper}"
    )


def test_bootstrap_script_executes_required_algorithm_on_fresh_data():
    # Use unpredictable probe observations so a script that merely exists or embeds
    # the answers for the shipped CSV cannot pass.
    probe_rng = np.random.default_rng(int.from_bytes(os.urandom(16), "big"))
    probe = probe_rng.normal(31.0, 7.0, 500)

    saved_random_state = np.random.get_state()
    np.random.seed(42)
    expected_means = np.asarray([
        np.mean(np.random.choice(probe, size=len(probe), replace=True))
        for _ in range(10000)
    ])
    expected_lower = float(np.percentile(expected_means, 2.5))
    expected_upper = float(np.percentile(expected_means, 97.5))
    np.random.set_state(saved_random_state)

    with open(OBSERVATIONS, "rb") as f:
        original_observations = f.read()
    original_results = None
    if os.path.exists(RESULTS):
        with open(RESULTS, "rb") as f:
            original_results = f.read()

    original_seed = np.random.seed
    original_choice = np.random.choice
    original_percentile = np.percentile
    events = []
    percentile_calls = []

    def recording_seed(value=None):
        events.append(("seed", value))
        return original_seed(value)

    def recording_choice(*args, **kwargs):
        events.append(("choice", None))
        return original_choice(*args, **kwargs)

    def recording_percentile(values, q, *args, **kwargs):
        result = original_percentile(values, q, *args, **kwargs)
        percentile_calls.append((np.asarray(values, dtype=float).copy(), q, result))
        return result

    with open(OBSERVATIONS, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["id", "intensity"])
        for index, value in enumerate(probe):
            writer.writerow([index, repr(float(value))])

    stdout = io.StringIO()
    old_argv = sys.argv[:]
    np.random.seed = recording_seed
    np.random.choice = recording_choice
    np.percentile = recording_percentile
    sys.argv = [BOOTSTRAP]
    try:
        with contextlib.redirect_stdout(stdout):
            runpy.run_path(BOOTSTRAP, run_name="__main__")
    except SystemExit as exc:
        assert exc.code in (None, 0), f"bootstrap_ci.py exited with status {exc.code}"
    finally:
        np.random.seed = original_seed
        np.random.choice = original_choice
        np.percentile = original_percentile
        sys.argv = old_argv
        with open(OBSERVATIONS, "wb") as f:
            f.write(original_observations)
        if original_results is None:
            if os.path.exists(RESULTS):
                os.remove(RESULTS)
        else:
            with open(RESULTS, "wb") as f:
                f.write(original_results)

    first_choice = next((i for i, event in enumerate(events) if event[0] == "choice"), None)
    assert first_choice is not None, "bootstrap_ci.py did not generate bootstrap resamples."
    assert first_choice > 0 and events[first_choice - 1] == ("seed", 42), (
        "numpy.random.seed(42) must be set immediately before generating resamples."
    )

    matching_distribution_calls = []
    for values, q, result in percentile_calls:
        flattened = values.reshape(-1)
        if flattened.size == 10000 and np.allclose(
            flattened, expected_means, rtol=0.0, atol=1e-12
        ):
            matching_distribution_calls.append((np.asarray(q), np.asarray(result)))

    assert matching_distribution_calls, (
        "bootstrap_ci.py did not compute percentiles from the 10,000 expected "
        "resampled means for the supplied observations."
    )

    saw_lower = False
    saw_upper = False
    for q, result in matching_distribution_calls:
        for quantile, value in zip(q.reshape(-1), result.reshape(-1)):
            if float(quantile) == 2.5 and math.isclose(
                float(value), expected_lower, rel_tol=0.0, abs_tol=1e-12
            ):
                saw_lower = True
            if float(quantile) == 97.5 and math.isclose(
                float(value), expected_upper, rel_tol=0.0, abs_tol=1e-12
            ):
                saw_upper = True

    assert saw_lower, "bootstrap_ci.py did not calculate the 2.5th percentile."
    assert saw_upper, "bootstrap_ci.py did not calculate the 97.5th percentile."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
