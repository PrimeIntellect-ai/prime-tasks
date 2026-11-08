#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import stat
import subprocess

import numpy as np
import pandas as pd
from scipy.integrate import solve_ivp

ANALYSIS = "/home/user/analysis.py"
PIPELINE = "/home/user/run_pipeline.sh"
RESULTS = "/home/user/results.json"
DATA = "/home/user/observed_data.csv"
VENV_PYTHON = "/home/user/venv/bin/python"


def sir(t, y, beta, gamma, N):
    S, I, R = y
    return [-beta * S * I / N,
            beta * S * I / N - gamma * I,
            gamma * I]


def trajectories():
    t_eval = np.arange(51)
    common = ((0, 50), [995, 5, 0])
    h0 = solve_ivp(sir, common[0], common[1],
                   args=(0.25, 0.10, 1000), t_eval=t_eval)
    h1 = solve_ivp(sir, common[0], common[1],
                   args=(0.40, 0.20, 1000), t_eval=t_eval)
    return t_eval, h0.y[1], h1.y[1]


def expected_values(data_path):
    df = pd.read_csv(data_path)
    observed = df["I_obs"].to_numpy()
    t_eval, i_h0, i_h1 = trajectories()

    sse_h0 = np.sum((i_h0 - observed) ** 2)
    sse_h1 = np.sum((i_h1 - observed) ** 2)
    if sse_h0 < sse_h1:
        best_hypothesis, best_sse, best_i = "H0", sse_h0, i_h0
    else:
        best_hypothesis, best_sse, best_i = "H1", sse_h1, i_h1

    np.random.seed(42)
    peaks = []
    for _ in range(1000):
        noise = np.random.normal(0, 5, size=len(t_eval))
        peaks.append(np.max(np.clip(best_i + noise, 0, None)))

    return {
        "best_hypothesis": best_hypothesis,
        "sse": round(float(best_sse), 2),
        "peak_mean": round(float(np.mean(peaks)), 2),
        "peak_std": round(float(np.std(peaks)), 2),
    }


def load_and_check_results(expected):
    assert os.path.exists(RESULTS), f"Missing {RESULTS}"
    try:
        with open(RESULTS, "r") as f:
            results = json.load(f)
    except json.JSONDecodeError:
        raise AssertionError(f"{RESULTS} is not a valid JSON file")

    expected_keys = {"best_hypothesis", "sse", "peak_mean", "peak_std"}
    assert set(results.keys()) == expected_keys, \
        f"JSON keys must be exactly {expected_keys}"
    assert results["best_hypothesis"] in ["H0", "H1"], \
        "best_hypothesis must be 'H0' or 'H1'"
    assert results["best_hypothesis"] == expected["best_hypothesis"], \
        "Incorrect best_hypothesis"
    assert math.isclose(results["sse"], expected["sse"], rel_tol=1e-2), \
        f"Expected SSE ~{expected['sse']}, got {results['sse']}"
    assert math.isclose(results["peak_mean"], expected["peak_mean"], rel_tol=1e-2), \
        f"Expected peak_mean ~{expected['peak_mean']}, got {results['peak_mean']}"
    assert math.isclose(results["peak_std"], expected["peak_std"], rel_tol=1e-2), \
        f"Expected peak_std ~{expected['peak_std']}, got {results['peak_std']}"


def write_challenge_data():
    t_eval, i_h0, i_h1 = trajectories()
    seed = int.from_bytes(os.urandom(8), "big")
    rng = np.random.default_rng(seed)
    base = i_h0 if rng.integers(0, 2) == 0 else i_h1
    sigma = rng.uniform(1.0, 8.0)
    observed = np.clip(base + rng.normal(0, sigma, len(t_eval)), 0, None)
    pd.DataFrame({"t": t_eval, "I_obs": observed}).to_csv(DATA, index=False)
    return expected_values(DATA)


def remove_results():
    try:
        os.remove(RESULTS)
    except FileNotFoundError:
        pass


def test_run_pipeline_exists_and_executable():
    assert os.path.exists(PIPELINE), f"Missing {PIPELINE}"
    st = os.stat(PIPELINE)
    assert bool(st.st_mode & stat.S_IXUSR), f"{PIPELINE} is not executable"


def test_analysis_script_exists():
    assert os.path.exists(ANALYSIS), f"Missing {ANALYSIS}"


def test_venv_exists():
    assert os.path.exists(VENV_PYTHON), \
        "Virtual environment python executable not found at /home/user/venv/bin/python"
    assert os.path.isfile("/home/user/venv/pyvenv.cfg"), \
        "/home/user/venv is not a Python virtual environment"


def test_results_json_structure_and_values():
    # Preserve the original check against the supplied dataset and existing output.
    load_and_check_results(expected_values(DATA))


def test_pipeline_and_analysis_execute_on_fresh_inputs():
    with open(DATA, "rb") as f:
        original_data = f.read()
    original_results = None
    if os.path.exists(RESULTS):
        with open(RESULTS, "rb") as f:
            original_results = f.read()

    try:
        # Execute the requested pipeline on a fresh, unpredictable dataset.
        expected = write_challenge_data()
        remove_results()
        proc = subprocess.run(
            ["/usr/sbin/runuser", "-u", "user", "--", "/bin/bash", PIPELINE],
            cwd="/home/user", capture_output=True, text=True, timeout=300
        )
        assert proc.returncode == 0, \
            f"run_pipeline.sh failed:\nSTDOUT:\n{proc.stdout}\nSTDERR:\n{proc.stderr}"
        load_and_check_results(expected)

        # Independently execute analysis.py through the created virtual environment.
        expected = write_challenge_data()
        remove_results()
        proc = subprocess.run(
            ["/usr/sbin/runuser", "-u", "user", "--", VENV_PYTHON, ANALYSIS],
            cwd="/home/user", capture_output=True, text=True, timeout=120
        )
        assert proc.returncode == 0, \
            f"analysis.py failed:\nSTDOUT:\n{proc.stdout}\nSTDERR:\n{proc.stderr}"
        load_and_check_results(expected)
    finally:
        with open(DATA, "wb") as f:
            f.write(original_data)
        if original_results is None:
            remove_results()
        else:
            with open(RESULTS, "wb") as f:
                f.write(original_results)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
