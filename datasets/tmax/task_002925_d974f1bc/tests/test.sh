#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import importlib.util
import inspect
import math
import os
import secrets
import subprocess
import sys
import time

import numpy as np
import pytest

SCRIPT_PATH = "/home/user/mcmc_mutations.py"
FASTA_PATH = "/home/user/data.fasta"
POSTERIOR_PATH = "/home/user/posterior_mean.txt"


def load_submission():
    assert os.path.isfile(SCRIPT_PATH), f"Missing file: {SCRIPT_PATH}"
    spec = importlib.util.spec_from_file_location("submitted_mcmc_mutations", SCRIPT_PATH)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def read_fasta_independent(path):
    sequences = []
    seq = ""
    with open(path, "r") as f:
        for line in f:
            if line.startswith(">"):
                if seq:
                    sequences.append(seq)
                seq = ""
            else:
                seq += line.strip()
        if seq:
            sequences.append(seq)
    return sequences


def distances_independent(sequences):
    n = len(sequences)
    result = np.zeros((n, n), dtype=int)
    for i in range(n):
        for j in range(i + 1, n):
            d = sum(a != b for a, b in zip(sequences[i], sequences[j]))
            result[i, j] = d
            result[j, i] = d
    return result


def reference_log_likelihood(distances, mu, length):
    upper = np.triu_indices(distances.shape[0], 1)
    d = np.asarray(distances, dtype=float)[upper]
    return float(np.sum(d * np.log(mu) + (length - d) * np.log1p(-mu)))


def reference_mcmc(distances, length, iterations=1000, seed=42):
    np.random.seed(seed)
    current = 0.5
    samples = []
    for _ in range(iterations):
        proposal = np.random.normal(current, 0.01)
        if proposal <= 0.001 or proposal >= 0.999:
            samples.append(current)
            continue

        log_current = reference_log_likelihood(distances, current, length)
        log_proposal = reference_log_likelihood(distances, proposal, length)
        if np.log(np.random.uniform(0, 1)) < log_proposal - log_current:
            current = proposal
        samples.append(current)
    return samples


def test_bottleneck_txt():
    bottleneck_path = "/home/user/bottleneck.txt"
    assert os.path.isfile(bottleneck_path), f"Missing file: {bottleneck_path}"
    with open(bottleneck_path, "r") as f:
        content = f.read().strip()
    assert content == "compute_distances", \
        f"Expected bottleneck function to be 'compute_distances', but got '{content}'"


def test_mcmc_mutations_modifications():
    assert os.path.isfile(SCRIPT_PATH), f"Missing file: {SCRIPT_PATH}"
    with open(SCRIPT_PATH, "r") as f:
        content = f.read()

    # Preserve the original source assertions.
    assert "prob *= (mu**d) * ((1-mu)**(L-d))" not in content, \
        "The script still contains the raw likelihood multiplication which causes underflow."
    assert "np.log(" in content or "math.log(" in content, \
        "The script does not seem to use log-likelihood."

    try:
        tree = ast.parse(content, filename=SCRIPT_PATH)
    except SyntaxError as exc:
        pytest.fail(f"The submitted script is not valid Python: {exc}")

    functions = [n for n in tree.body if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef))]
    compute = next((n for n in functions if n.name == "compute_distances"), None)
    assert compute is not None, "Missing compute_distances function"
    loop_nodes = [n for n in ast.walk(compute) if isinstance(n, (ast.For, ast.AsyncFor, ast.While))]
    assert not loop_nodes, "compute_distances still uses explicit Python loops instead of NumPy vectorization"


def test_compute_distances_is_correct_and_fast_vectorized():
    module = load_submission()
    assert callable(getattr(module, "compute_distances", None))

    entropy = secrets.randbits(64)
    rng = np.random.default_rng(entropy)
    alphabet = np.array(list("ACGT"))

    small = ["".join(row) for row in rng.choice(alphabet, size=(37, 91))]
    expected = distances_independent(small)
    actual = np.asarray(module.compute_distances(small))
    assert actual.shape == expected.shape
    assert np.array_equal(actual, expected), "compute_distances returned incorrect Hamming distances"
    assert np.array_equal(actual, actual.T), "Distance matrix is not symmetric"
    assert np.all(np.diag(actual) == 0), "Distance matrix diagonal must be zero"

    # Exercise enough data to distinguish array vectorization from nested Python work.
    perf_sequences = ["".join(row) for row in rng.choice(alphabet, size=(260, 180))]
    start = time.perf_counter()
    baseline = distances_independent(perf_sequences)
    baseline_time = time.perf_counter() - start

    timings = []
    optimized_result = None
    for _ in range(2):
        start = time.perf_counter()
        optimized_result = np.asarray(module.compute_distances(perf_sequences))
        timings.append(time.perf_counter() - start)

    assert np.array_equal(optimized_result, baseline)
    optimized_time = min(timings)
    assert optimized_time < baseline_time * 0.5, \
        f"compute_distances is not significantly faster than nested Python loops ({optimized_time:.4f}s vs {baseline_time:.4f}s)"


def test_run_mcmc_matches_independent_log_probability_sampler():
    module = load_submission()
    run_mcmc = getattr(module, "run_mcmc", None)
    assert callable(run_mcmc), "Missing run_mcmc function"

    signature = inspect.signature(run_mcmc)
    assert signature.parameters["iterations"].default == 1000, "The default iteration count was changed"
    assert signature.parameters["seed"].default == 42, "The default random seed was changed"

    entropy = secrets.randbits(64)
    rng = np.random.default_rng(entropy)
    alphabet = np.array(list("ACGT"))
    length = 140
    base = rng.choice(alphabet, size=length)
    sequences = []
    for _ in range(32):
        row = base.copy()
        mask = rng.random(length) < 0.08
        row[mask] = rng.choice(alphabet, size=int(mask.sum()))
        sequences.append("".join(row))

    distances = distances_independent(sequences)
    expected = np.asarray(reference_mcmc(distances, length, iterations=180, seed=317), dtype=float)
    actual = np.asarray(run_mcmc(distances.copy(), length, iterations=180, seed=317), dtype=float)

    assert actual.shape == expected.shape, "run_mcmc returned the wrong number of samples"
    assert np.all(np.isfinite(actual)), "run_mcmc produced non-finite samples"
    assert np.all((actual > 0.001) & (actual < 0.999)), "run_mcmc produced samples outside the prior bounds"
    assert np.allclose(actual, expected, rtol=0, atol=1e-12), \
        "run_mcmc does not implement the required log-probability Metropolis-Hastings updates"


def test_script_execution_regenerates_correct_posterior_mean():
    assert os.path.isfile(FASTA_PATH), f"Missing file: {FASTA_PATH}"
    if os.path.exists(POSTERIOR_PATH):
        os.remove(POSTERIOR_PATH)

    completed = subprocess.run(
        [sys.executable, SCRIPT_PATH],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert completed.returncode == 0, \
        f"Script execution failed. stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    assert os.path.isfile(POSTERIOR_PATH), \
        "Running mcmc_mutations.py did not create posterior_mean.txt"

    sequences = read_fasta_independent(FASTA_PATH)
    distances = distances_independent(sequences)
    expected = round(float(np.mean(reference_mcmc(distances, len(sequences[0])))), 4)

    with open(POSTERIOR_PATH, "r") as f:
        content = f.read().strip()
    try:
        value = float(content)
    except ValueError:
        pytest.fail(f"Could not parse float from {POSTERIOR_PATH}, content: '{content}'")

    assert math.isfinite(value)
    assert math.isclose(value, expected, abs_tol=5e-5), \
        f"Expected independently derived posterior mean {expected:.4f}, got {value}"
    # Preserve the original known-result assertion for the supplied FASTA data.
    assert math.isclose(value, 0.0768, abs_tol=1e-4), \
        f"Expected posterior mean around 0.0768, got {value}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
