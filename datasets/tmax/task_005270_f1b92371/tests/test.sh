#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import shutil
import subprocess
import textwrap

import numpy as np
import pandas as pd
import pytest

PROJECT_DIR = "/home/user/spectroscopy_project"
OPTIMIZE = os.path.join(PROJECT_DIR, "optimize.sh")
PIPELINE = os.path.join(PROJECT_DIR, "pipeline.sh")
LOSS_PY = os.path.join(PROJECT_DIR, "loss.py")
DATA_FILE = os.path.join(PROJECT_DIR, "data.csv")
RESULTS_FILE = os.path.join(PROJECT_DIR, "results.txt")
TRACE_FILE = "/tmp/optimizer_loss_calls.txt"


def run(cmd, timeout=90):
    return subprocess.run(
        cmd, cwd=PROJECT_DIR, text=True, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, timeout=timeout, check=True
    )


def parse_results(path):
    assert os.path.isfile(path), f"The results file {path} was not found. Did you run the pipeline?"
    lines = [line.strip() for line in open(path) if line.strip()]
    assert len(lines) == 3, "results.txt must contain exactly three non-empty lines"
    expected_keys = ["mu", "sigma", "loss"]
    results = {}
    for line, expected_key in zip(lines, expected_keys):
        assert "=" in line, f"Malformed results line: {line}"
        key, value = line.split("=", 1)
        assert key.strip() == expected_key, f"Expected '{expected_key}=...' in results.txt"
        try:
            results[expected_key] = float(value.strip())
        except ValueError:
            pytest.fail(f"Value for {expected_key} is not a valid float: {value}")
    return results


def close(a, b, atol=2e-4):
    return abs(a - b) <= atol * max(1.0, abs(a), abs(b))


def test_optimizer_and_pipeline():
    assert os.path.isfile(OPTIMIZE), "optimize.sh is missing"
    assert os.path.isfile(PIPELINE), "pipeline.sh is missing"

    # Exercise optimize.sh against a deterministic objective. Its trace must follow
    # the requested accept/reject and learning-rate-halving state machine.
    original_loss = open(LOSS_PY, "rb").read()
    if os.path.exists(TRACE_FILE):
        os.remove(TRACE_FILE)
    oracle = textwrap.dedent(f'''\
        import math
        import sys
        mu = float(sys.argv[1])
        sigma = float(sys.argv[2])
        with open({TRACE_FILE!r}, "a") as f:
            f.write("{{:.17g}} {{:.17g}}\\n".format(mu, sigma))
        if sigma <= 0 or not math.isfinite(mu) or not math.isfinite(sigma):
            print("NaN NaN NaN")
        else:
            # loss = 2*((mu-5)^2 + (sigma-1.2)^2)
            loss = 2.0*((mu-5.0)**2 + (sigma-1.2)**2)
            grad_mu = 4.0*(mu-5.0)
            grad_sigma = 4.0*(sigma-1.2)
            print("{{:.12g}} {{:.12g}} {{:.12g}}".format(loss, grad_mu, grad_sigma))
    ''')
    try:
        with open(LOSS_PY, "w") as f:
            f.write(oracle)
        if os.path.exists(RESULTS_FILE):
            os.remove(RESULTS_FILE)
        run(["bash", "optimize.sh"], timeout=30)
        assert os.path.isfile(TRACE_FILE), "optimize.sh did not call loss.py"
        calls = []
        with open(TRACE_FILE) as f:
            for line in f:
                fields = line.split()
                assert len(fields) == 2
                calls.append((float(fields[0]), float(fields[1])))
        assert calls, "No loss evaluations were made"
        assert close(calls[0][0], 4.0) and close(calls[0][1], 1.0), \
            "Optimization must initialize mu=4.0 and sigma=1.0"

        current_mu, current_sigma = calls[0]
        current_loss = 2.0*((current_mu-5.0)**2 + (current_sigma-1.2)**2)
        lr = 1.0
        attempts = 0
        saw_rejection = False
        saw_acceptance = False

        for new_mu, new_sigma in calls[1:]:
            assert attempts < 100, "Optimizer performed more than 100 iterations"
            assert lr >= 1e-5, "Optimizer continued after lr fell below 1e-5"
            grad_mu = 4.0*(current_mu-5.0)
            grad_sigma = 4.0*(current_sigma-1.2)
            expected_mu = current_mu - lr*grad_mu
            expected_sigma = current_sigma - lr*grad_sigma
            assert close(new_mu, expected_mu), \
                f"Incorrect mu step: got {new_mu}, expected {expected_mu} with lr={lr}"
            assert close(new_sigma, expected_sigma), \
                f"Incorrect sigma step: got {new_sigma}, expected {expected_sigma} with lr={lr}"

            new_loss = 2.0*((new_mu-5.0)**2 + (new_sigma-1.2)**2)
            if new_loss < current_loss - 1e-9:
                current_mu, current_sigma, current_loss = new_mu, new_sigma, new_loss
                saw_acceptance = True
            else:
                lr *= 0.5
                saw_rejection = True
            attempts += 1

        assert saw_rejection, "Backtracking rejection/learning-rate shrink was not exercised"
        assert saw_acceptance, "No improving step was accepted"
        assert lr < 1e-5 or attempts == 100, \
            "Optimizer stopped without reaching 100 iterations or lr < 1e-5"

        behavioral = parse_results(RESULTS_FILE)
        assert close(behavioral["mu"], current_mu)
        assert close(behavioral["sigma"], current_sigma)
        assert close(behavioral["loss"], current_loss)
    finally:
        with open(LOSS_PY, "wb") as f:
            f.write(original_loss)

    # Run the requested real pipeline from a clean output state.
    for path in (DATA_FILE, RESULTS_FILE):
        if os.path.exists(path):
            os.remove(path)
    run(["bash", "pipeline.sh"])
    assert os.path.isfile(DATA_FILE), "pipeline.sh did not generate data.csv"
    assert os.path.isfile(RESULTS_FILE), "pipeline.sh did not generate results.txt"

    # Also run the verified optimizer directly on the generated real data so the
    # final report is demonstrably produced by optimize.sh rather than fabricated.
    os.remove(RESULTS_FILE)
    run(["bash", "optimize.sh"])
    results = parse_results(RESULTS_FILE)

    mu, sigma, reported_loss = results["mu"], results["sigma"], results["loss"]
    assert all(math.isfinite(v) for v in (mu, sigma, reported_loss)), \
        "mu, sigma, and loss must be finite numbers"

    # Confirm data.csv is the deterministic signal the supplied generator defines.
    df = pd.read_csv(DATA_FILE)
    assert list(df.columns) == ["x", "y"] and len(df) == 100, "Unexpected data.csv format"
    np.random.seed(42)
    expected_x = np.linspace(0, 10, 100)
    expected_y = np.exp(-0.5*((expected_x-5.0)/1.2)**2)/(1.2*np.sqrt(2*np.pi))
    expected_y += np.random.normal(0, 0.01, size=len(expected_x))
    expected_y = np.clip(expected_y, 1e-8, None)
    expected_y /= np.sum(expected_y)
    assert np.allclose(df["x"].to_numpy(), expected_x, rtol=0, atol=1e-12)
    assert np.allclose(df["y"].to_numpy(), expected_y, rtol=0, atol=1e-12)

    # Independently recompute KL loss from data.csv and the submitted parameters.
    x = df["x"].to_numpy()
    y_obs = df["y"].to_numpy()
    assert sigma > 0, "sigma must be positive"
    y_mod = np.exp(-0.5*((x-mu)/sigma)**2)/(sigma*np.sqrt(2*np.pi))
    y_mod = np.clip(y_mod, 1e-8, None)
    y_mod /= np.sum(y_mod)
    actual_loss = float(np.sum(y_obs*np.log(y_obs/y_mod)))
    assert math.isclose(reported_loss, actual_loss, rel_tol=1e-4, abs_tol=1e-6), \
        f"Reported loss {reported_loss} does not match recomputed loss {actual_loss}"

    # Preserve the original verifier's convergence assertions.
    assert 4.8 <= mu <= 5.2, f"mu ({mu}) is not within the expected range [4.8, 5.2]."
    assert 1.0 <= sigma <= 1.4, f"sigma ({sigma}) is not within the expected range [1.0, 1.4]."
    assert reported_loss < 0.1, f"loss ({reported_loss}) is not less than 0.1."

    initial_sigma = 1.0
    initial_mod = np.exp(-0.5*((x-4.0)/initial_sigma)**2)/(initial_sigma*np.sqrt(2*np.pi))
    initial_mod = np.clip(initial_mod, 1e-8, None)
    initial_mod /= np.sum(initial_mod)
    initial_loss = float(np.sum(y_obs*np.log(y_obs/initial_mod)))
    assert actual_loss < initial_loss, "Optimization did not improve on the initial parameters"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
