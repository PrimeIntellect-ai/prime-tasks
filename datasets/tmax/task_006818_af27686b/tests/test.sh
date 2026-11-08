#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import subprocess

import h5py
import numpy as np

SOURCE = "/home/user/analyze_energies.cpp"
EXECUTABLE = "/home/user/analyze_energies"
RESULTS = "/home/user/analysis_results.json"
DATASET = "/home/user/sim_data.h5"
REBUILT = "/tmp/analyze_energies_rebuilt"

EXPECTED_KEYS = {
    "mean", "variance", "log_likelihood_gaussian",
    "log_likelihood_exponential", "aic_gaussian",
    "aic_exponential", "best_fit"
}


def load_results():
    assert os.path.isfile(RESULTS), f"Results file {RESULTS} is missing."
    try:
        with open(RESULTS, "r") as f:
            results = json.load(f)
    except json.JSONDecodeError as exc:
        raise AssertionError(f"File {RESULTS} does not contain valid JSON: {exc}")
    missing_keys = EXPECTED_KEYS - results.keys()
    assert not missing_keys, f"JSON results are missing keys: {missing_keys}"
    return results


def expected_for(data):
    values = [float(x) for x in data]
    n = len(values)
    mean = math.fsum(values) / n
    variance = math.fsum((x - mean) ** 2 for x in values) / (n - 1)
    ll_gaussian = math.fsum(
        -0.5 * math.log(2.0 * math.pi * variance)
        - ((x - mean) ** 2) / (2.0 * variance)
        for x in values
    )
    rate = 1.0 / mean
    ll_exponential = math.fsum(math.log(rate) - rate * x for x in values)
    aic_gaussian = 4.0 - 2.0 * ll_gaussian
    aic_exponential = 2.0 - 2.0 * ll_exponential
    return {
        "mean": mean,
        "variance": variance,
        "log_likelihood_gaussian": ll_gaussian,
        "log_likelihood_exponential": ll_exponential,
        "aic_gaussian": aic_gaussian,
        "aic_exponential": aic_exponential,
        "best_fit": "gaussian" if aic_gaussian < aic_exponential else "exponential",
    }


def assert_matches(results, expected):
    for key in EXPECTED_KEYS - {"best_fit"}:
        value = results.get(key)
        assert isinstance(value, (int, float)) and not isinstance(value, bool), \
            f"{key} must be numeric, got {value!r}"
        assert math.isfinite(float(value)), f"{key} must be finite, got {value!r}"
        assert math.isclose(float(value), expected[key], rel_tol=2e-6, abs_tol=2e-3), \
            f"{key} value {value!r} is incorrect; expected {expected[key]!r}"
    best_fit = results.get("best_fit")
    assert isinstance(best_fit, str), f"best_fit must be a string, got {best_fit!r}"
    assert best_fit.lower() == expected["best_fit"], \
        f"best_fit should be {expected['best_fit']!r}, got {best_fit!r}"


def write_dataset(data):
    with h5py.File(DATASET, "w") as f:
        f.create_dataset("energies", data=np.asarray(data, dtype=np.float64))


def run_and_check(program, data):
    write_dataset(data)
    if os.path.exists(RESULTS):
        os.remove(RESULTS)
    completed = subprocess.run(
        [program], cwd="/home/user", stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, timeout=30
    )
    assert completed.returncode == 0, \
        f"{program} exited with {completed.returncode}. stderr: {completed.stderr}"
    assert os.path.isfile(RESULTS), f"{program} did not create {RESULTS}"
    assert_matches(load_results(), expected_for(data))


def test_complete_pipeline():
    assert os.path.isfile(SOURCE), f"C++ source file {SOURCE} is missing."
    assert os.path.isfile(EXECUTABLE), f"Executable {EXECUTABLE} is missing."
    assert os.access(EXECUTABLE, os.X_OK), f"File {EXECUTABLE} is not executable."
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{EXECUTABLE} is not a compiled ELF executable."

    # Preserve the original verifier's checks on the result produced by the agent.
    original_results = load_results()
    assert math.isclose(original_results.get("mean", 0), 4.99757, rel_tol=1e-3, abs_tol=1e-2), \
        f"Mean value {original_results.get('mean')} is incorrect."
    assert math.isclose(original_results.get("variance", 0), 1.44229, rel_tol=1e-3, abs_tol=1e-2), \
        f"Variance value {original_results.get('variance')} is incorrect."
    assert math.isclose(original_results.get("log_likelihood_gaussian", 0), -15949.72, rel_tol=1e-3, abs_tol=1.0), \
        f"Gaussian Log-Likelihood {original_results.get('log_likelihood_gaussian')} is incorrect."
    assert math.isclose(original_results.get("log_likelihood_exponential", 0), -26090.73, rel_tol=1e-3, abs_tol=1.0), \
        f"Exponential Log-Likelihood {original_results.get('log_likelihood_exponential')} is incorrect."
    assert math.isclose(original_results.get("aic_gaussian", 0), 31903.44, rel_tol=1e-3, abs_tol=1.0), \
        f"Gaussian AIC {original_results.get('aic_gaussian')} is incorrect."
    assert math.isclose(original_results.get("aic_exponential", 0), 52183.46, rel_tol=1e-3, abs_tol=1.0), \
        f"Exponential AIC {original_results.get('aic_exponential')} is incorrect."
    best_fit = original_results.get("best_fit", "")
    assert isinstance(best_fit, str) and best_fit.lower() == "gaussian", \
        f"Best fit should be 'gaussian', got {best_fit!r}."

    with open(DATASET, "rb") as f:
        original_h5 = f.read()
    with open(RESULTS, "rb") as f:
        original_json = f.read()

    try:
        build = subprocess.run(
            ["h5c++", "-std=c++11", SOURCE, "-o", REBUILT],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=60
        )
        assert build.returncode == 0, \
            f"The submitted C++ source does not compile. stderr: {build.stderr}"
        assert os.path.isfile(REBUILT) and os.access(REBUILT, os.X_OK)

        rng = np.random.default_rng(int.from_bytes(os.urandom(16), "little"))
        gaussian_data = rng.normal(
            loc=rng.uniform(6.5, 9.0), scale=rng.uniform(0.35, 1.0), size=10000
        ).astype(np.float64)
        exponential_data = rng.exponential(
            scale=rng.uniform(1.5, 4.5), size=10000
        ).astype(np.float64)

        # Exercise both the delivered executable and a fresh build of its source
        # on verifier-generated HDF5 inputs whose answers are computed here.
        for program in (EXECUTABLE, REBUILT):
            run_and_check(program, gaussian_data)
            run_and_check(program, exponential_data)
    finally:
        with open(DATASET, "wb") as f:
            f.write(original_h5)
        with open(RESULTS, "wb") as f:
            f.write(original_json)

TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
