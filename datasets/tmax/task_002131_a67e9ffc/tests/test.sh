#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import tempfile

import numpy as np
import pandas as pd
import pytest
from scipy.integrate import odeint

SCRIPT_PATH = "/home/user/evaluate_sim.py"


def model(y, t):
    A, B, C = y
    k1, k2 = 0.08, 0.15
    return [-k1 * A * B,
            -k1 * A * B - k2 * B,
            k1 * A * B + k2 * B]


def projected_noise(rng, rows, kind="gaussian"):
    if kind == "gaussian":
        noise = rng.normal(size=(rows, 3))
    elif kind == "uniform":
        noise = rng.uniform(-1.0, 1.0, size=(rows, 3))
    else:
        raise ValueError(kind)

    # Preserve A+B+C in every row while retaining Gaussian marginals for
    # valid files. Centering also removes chance sample-mean failures.
    noise -= noise.mean(axis=1, keepdims=True)
    noise -= noise.mean(axis=0, keepdims=True)
    scale = 0.02 / np.sqrt(np.mean(noise * noise))
    return noise * scale


def make_case(rng, bad_type=None):
    rows = int(rng.integers(340, 401))
    end_time = float(rng.uniform(0.004, 0.0075))
    t = np.linspace(0.0, end_time, rows)

    # These legal initial conditions and time spans keep the small drift in
    # the image's stated A+B+C law below its required 1e-3 tolerance.
    A0 = float(rng.uniform(0.15, 0.24))
    B0 = float(rng.uniform(2.2, 3.8))
    C0 = 15.0 - A0 - B0
    sol = odeint(model, [A0, B0, C0], t, rtol=1e-11, atol=1e-12)

    noise_kind = "uniform" if bad_type == "uniform" else "gaussian"
    noise = projected_noise(rng, rows - 1, noise_kind)
    observed = sol.copy()
    observed[1:] += noise

    if bad_type == "biased":
        observed[1:] += np.array([0.075, -0.035, -0.040])
    elif bad_type == "jump":
        observed[rows // 2:] += np.array([0.75, -0.35, -0.40])
    elif bad_type not in (None, "uniform"):
        raise ValueError(bad_type)

    df = pd.DataFrame(observed, columns=["A", "B", "C"])
    df.insert(0, "time", t)
    return df


def test_evaluate_sim_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"The script {SCRIPT_PATH} does not exist."


def test_randomized_hidden_corpus():
    seed = int.from_bytes(secrets.token_bytes(16), "big")
    rng = np.random.default_rng(seed)

    cases = [(None, 0) for _ in range(6)]
    cases += [("uniform", 1) for _ in range(3)]
    cases += [("biased", 1) for _ in range(3)]
    cases += [("jump", 1) for _ in range(3)]
    rng.shuffle(cases)

    failures = []
    with tempfile.TemporaryDirectory(prefix="trajectory_check_") as workdir:
        for bad_type, expected_code in cases:
            filename = secrets.token_hex(16) + ".csv"
            path = os.path.join(workdir, filename)
            make_case(rng, bad_type).to_csv(path, index=False)

            try:
                result = subprocess.run(
                    ["python3", SCRIPT_PATH, path],
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    timeout=20,
                )
                actual = result.returncode
            except subprocess.TimeoutExpired:
                actual = "timeout"

            if actual != expected_code:
                category = "valid" if expected_code == 0 else "corrupted"
                failures.append(f"{filename} ({category}) returned {actual}")

    if failures:
        pytest.fail("Incorrect classifications: " + " | ".join(failures))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
