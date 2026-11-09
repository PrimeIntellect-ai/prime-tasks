#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import stat
import subprocess

import numpy as np
from scipy.integrate import odeint

SCRIPT_FILE = "/home/user/fit_mcmc.py"
DATA_FILE = "/home/user/protein_data.json"
RESULTS_FILE = "/home/user/posterior_results.txt"


def test_posterior_results_file():
    """Check if the posterior_results.txt file exists and contains the correct deterministic values."""
    results_file = "/home/user/posterior_results.txt"
    assert os.path.isfile(results_file), f"Results file {results_file} does not exist. Did you run the script?"

    with open(results_file, "r") as f:
        content = f.read().strip()

    assert "alpha: 2.4939" in content, f"Expected 'alpha: 2.4939' not found in results. Found: {content}"
    assert "beta: 0.4990" in content, f"Expected 'beta: 0.4990' not found in results. Found: {content}"


def test_script_fixed():
    """Check if the script was modified to fix the non-deterministic iteration."""
    script_file = "/home/user/fit_mcmc.py"
    assert os.path.isfile(script_file), f"Script file {script_file} does not exist."

    with open(script_file, "r") as f:
        content = f.read()

    # The script should sort the sequence identifiers to ensure deterministic iteration.
    # We check that the sorting logic is present or the buggy set iteration is removed.
    has_sorted = "sorted(" in content
    has_buggy_set = "unique_seqs = set(data.keys())" in content and "for seq in unique_seqs:" in content

    assert has_sorted or not has_buggy_set, \
        "The script still appears to iterate over an unordered set. You must sort the sequence identifiers."


def reference_result(data):
    """Independently run the specified MCMC using a deterministic reduction order."""
    def model(c, t, alpha, beta):
        return alpha - beta * c

    def log_likelihood(alpha, beta):
        if alpha < 0 or beta < 0:
            return -np.inf
        total_error = 0.0
        for seq in sorted(data.keys()):
            t = np.array(data[seq]["t"])
            c_obs = np.array(data[seq]["c"])
            c_pred = odeint(model, 0, t, args=(alpha, beta)).flatten()
            total_error += np.sum((c_obs - c_pred) ** 2)
        return -0.5 * total_error

    np.random.seed(42)
    alpha_current, beta_current = 1.0, 1.0
    ll_current = log_likelihood(alpha_current, beta_current)
    chain = []
    for _ in range(1500):
        alpha_prop = alpha_current + np.random.normal(0, 0.1)
        beta_prop = beta_current + np.random.normal(0, 0.05)
        ll_prop = log_likelihood(alpha_prop, beta_prop)
        if np.log(np.random.uniform()) < (ll_prop - ll_current):
            alpha_current = alpha_prop
            beta_current = beta_prop
            ll_current = ll_prop
        chain.append([alpha_current, beta_current])

    chain = np.array(chain[500:])
    return f"alpha: {np.mean(chain[:, 0]):.4f}, beta: {np.mean(chain[:, 1]):.4f}"


def run_submission(hash_seed):
    if os.path.lexists(RESULTS_FILE):
        os.unlink(RESULTS_FILE)

    env = os.environ.copy()
    env["PYTHONHASHSEED"] = str(hash_seed)
    env["PYTHONDONTWRITEBYTECODE"] = "1"
    completed = subprocess.run(
        ["python3", SCRIPT_FILE],
        cwd="/home/user",
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=240,
    )
    assert completed.returncode == 0, f"fit_mcmc.py failed:\n{completed.stdout}"
    assert os.path.isfile(RESULTS_FILE), "Executing fit_mcmc.py did not create posterior_results.txt"
    with open(RESULTS_FILE, "r") as f:
        result = f.read().strip()
    assert re.fullmatch(r"alpha: -?\d+\.\d{4}, beta: -?\d+\.\d{4}", result), \
        f"Unexpected results format: {result!r}"
    return result


def make_unseen_data():
    """Create an input unknown until verification to detect hardcoded result writers."""
    seed = int.from_bytes(os.urandom(8), "big")
    rng = np.random.default_rng(seed)
    alpha = rng.uniform(1.6, 3.3)
    beta = rng.uniform(0.25, 0.8)
    data = {}
    for i in range(7):
        name = f"fragment_{rng.integers(10**8, 10**9)}_{i}"
        t = np.linspace(0, rng.uniform(7.0, 12.0), 25)
        c_true = (alpha / beta) * (1.0 - np.exp(-beta * t))
        c_obs = c_true + rng.normal(0, 0.35, size=len(t))
        data[name] = {"t": t.tolist(), "c": c_obs.tolist()}
    return data


def test_script_executes_reproducibly_and_computes_results():
    assert os.path.isfile(SCRIPT_FILE), f"Script file {SCRIPT_FILE} does not exist."
    mode = os.stat(SCRIPT_FILE).st_mode
    assert stat.S_ISREG(mode), f"{SCRIPT_FILE} is not a regular file"

    with open(DATA_FILE, "rb") as f:
        original_data_bytes = f.read()
    original_result_bytes = None
    if os.path.isfile(RESULTS_FILE):
        with open(RESULTS_FILE, "rb") as f:
            original_result_bytes = f.read()

    try:
        original_data = json.loads(original_data_bytes.decode("utf-8"))
        expected_original = reference_result(original_data)
        assert expected_original == "alpha: 2.4939, beta: 0.4990", \
            f"The supplied protein data no longer yields the required result: {expected_original}"

        # Actually execute the submitted artifact under distinct hash orders.
        with open(DATA_FILE, "wb") as f:
            f.write(original_data_bytes)
        result_seed_1 = run_submission(1)
        with open(DATA_FILE, "wb") as f:
            f.write(original_data_bytes)
        result_seed_2 = run_submission(8675309)

        assert result_seed_1 == expected_original, \
            f"Executed result is mathematically incorrect: expected {expected_original!r}, got {result_seed_1!r}"
        assert result_seed_2 == expected_original, \
            f"Result changed under another hash seed: expected {expected_original!r}, got {result_seed_2!r}"
        assert result_seed_1 == result_seed_2, "MCMC output is not reproducible across Python hash seeds"

        # Replace the dataset temporarily with an unseen input and derive its answer
        # independently, ensuring the script computes rather than hardcodes the values.
        unseen_data = make_unseen_data()
        expected_unseen = reference_result(unseen_data)
        with open(DATA_FILE, "w") as f:
            json.dump(unseen_data, f)
        actual_unseen = run_submission(314159)
        assert actual_unseen == expected_unseen, \
            f"Script did not compute the correct result for an unseen dataset: expected {expected_unseen!r}, got {actual_unseen!r}"
    finally:
        with open(DATA_FILE, "wb") as f:
            f.write(original_data_bytes)
        if original_result_bytes is None:
            if os.path.lexists(RESULTS_FILE):
                os.unlink(RESULTS_FILE)
        else:
            with open(RESULTS_FILE, "wb") as f:
                f.write(original_result_bytes)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
