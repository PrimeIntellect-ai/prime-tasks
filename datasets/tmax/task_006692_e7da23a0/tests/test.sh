#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import math
import subprocess
import numpy as np
import pytest
from scipy.integrate import solve_ivp
from scipy.stats import wasserstein_distance, wilcoxon

RESULT = "/home/user/analysis_results.json"
SIGNALS = "/home/user/experimental_signals.npy"
BASELINE = "/home/user/baseline_distances.npy"


def reference_results(signals, baseline):
    signals = np.asarray(signals)
    baseline = np.asarray(baseline)
    assert signals.shape == (10, 1000)
    assert baseline.shape == (10,)

    def model(t, y):
        t1, t2 = y
        return [-0.1 * (t1 - t2), 0.1 * (t1 - t2) - 0.05 * (t2 - 20.0)]

    times = np.arange(0.0, 100.0, 10.0)
    sol = solve_ivp(model, (0.0, 90.0), (1000.0, 300.0), t_eval=times)
    assert sol.success
    temperatures = sol.y[0]

    frequencies = np.arange(500, dtype=float)
    window = np.hanning(1000)
    distances = []
    for signal, temperature in zip(signals, temperatures):
        experimental = np.abs(np.fft.fft(signal * window)[:500])
        experimental = experimental / experimental.sum()

        mean = 0.2 * temperature
        sigma = 0.5 * np.sqrt(temperature)
        theoretical = np.exp(-0.5 * ((frequencies - mean) / sigma) ** 2)
        theoretical = theoretical / theoretical.sum()

        distances.append(wasserstein_distance(
            frequencies, frequencies,
            u_weights=experimental,
            v_weights=theoretical,
        ))

    distances = np.asarray(distances)
    p_value = float(wilcoxon(distances, baseline).pvalue)
    return temperatures, distances, p_value


def load_result():
    assert os.path.isfile(RESULT), f"File {RESULT} does not exist. The script must create this file."
    with open(RESULT, "r") as f:
        return json.load(f)


def result_matches(expected):
    try:
        data = load_result()
        t1 = np.asarray(data["t1_temperatures"], dtype=float)
        wd = np.asarray(data["wasserstein_distances"], dtype=float)
        pval = float(data["wilcoxon_p_value"])
    except Exception:
        return False

    exp_t1, exp_wd, exp_pval = expected
    return (
        t1.shape == (10,) and wd.shape == (10,) and
        np.all(np.isfinite(t1)) and np.all(np.isfinite(wd)) and math.isfinite(pval) and
        np.allclose(t1, exp_t1, rtol=1e-4, atol=0.5) and
        np.allclose(wd, exp_wd, rtol=1e-4, atol=0.15) and
        math.isclose(pval, exp_pval, rel_tol=0.0, abs_tol=1e-10)
    )


def candidate_scripts():
    candidates = []
    for root, dirs, files in os.walk("/home/user"):
        rel = os.path.relpath(root, "/home/user")
        depth = 0 if rel == "." else rel.count(os.sep) + 1
        dirs[:] = [d for d in dirs if not d.startswith(".")]
        if depth >= 3:
            dirs[:] = []
        for name in files:
            if not name.endswith(".py"):
                continue
            path = os.path.join(root, name)
            try:
                text = open(path, "r", errors="ignore").read()
            except OSError:
                text = ""
            candidates.append(("analysis_results.json" not in text, -os.path.getmtime(path), path))
    return [item[2] for item in sorted(candidates)]


def run_script(path):
    if os.path.exists(RESULT):
        os.remove(RESULT)
    return subprocess.run(
        ["python3", path], cwd="/home/user",
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=120,
    )


def test_00_script_executes_and_computes_pipeline():
    original_signals_bytes = open(SIGNALS, "rb").read()
    original_baseline_bytes = open(BASELINE, "rb").read()
    original_signals = np.load(SIGNALS)
    original_baseline = np.load(BASELINE)
    original_expected = reference_results(original_signals, original_baseline)

    scripts = candidate_scripts()
    assert scripts, "No Python analysis script was found under /home/user."

    chosen = None
    diagnostics = []
    for script in scripts:
        open(SIGNALS, "wb").write(original_signals_bytes)
        open(BASELINE, "wb").write(original_baseline_bytes)
        try:
            proc = run_script(script)
        except Exception as exc:
            diagnostics.append(f"{script}: {exc}")
            continue
        if proc.returncode == 0 and result_matches(original_expected):
            chosen = script
            break
        diagnostics.append(f"{script}: exit={proc.returncode}, stderr={proc.stderr[-300:]}")

    assert chosen is not None, "No submitted Python script produced the correct results when executed. " + " | ".join(diagnostics)

    try:
        rng = np.random.default_rng(731942)
        challenge_signals = rng.normal(0.0, 1.0, (10, 1000))
        x = np.arange(1000, dtype=float)
        for i in range(10):
            challenge_signals[i] += 0.7 * np.cos(2.0 * np.pi * (17 + 11 * i) * x / 1000.0)
        challenge_baseline = np.linspace(3.0, 12.0, 10)
        challenge_expected = reference_results(challenge_signals, challenge_baseline)
        np.save(SIGNALS, challenge_signals)
        np.save(BASELINE, challenge_baseline)

        proc = run_script(chosen)
        assert proc.returncode == 0, f"Analysis script failed on valid input: {proc.stderr}"
        assert result_matches(challenge_expected), "Analysis script did not recompute the required pipeline for changed valid inputs."
    finally:
        open(SIGNALS, "wb").write(original_signals_bytes)
        open(BASELINE, "wb").write(original_baseline_bytes)
        proc = run_script(chosen)
        assert proc.returncode == 0, f"Analysis script failed after restoring task inputs: {proc.stderr}"


def test_analysis_results_exists():
    """Check if the analysis_results.json file was created."""
    assert os.path.isfile(RESULT), f"File {RESULT} does not exist. The script must create this file."


def test_analysis_results_structure_and_types():
    """Validate the structure, keys, and types of the output JSON."""
    if not os.path.isfile(RESULT):
        pytest.skip("JSON file missing.")

    with open(RESULT, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("The file analysis_results.json is not valid JSON.")

    expected_keys = {"t1_temperatures", "wasserstein_distances", "wilcoxon_p_value"}
    actual_keys = set(data.keys())
    assert expected_keys.issubset(actual_keys), f"Missing keys in JSON. Expected {expected_keys}, found {actual_keys}."

    t1 = data["t1_temperatures"]
    wd = data["wasserstein_distances"]
    pval = data["wilcoxon_p_value"]

    assert isinstance(t1, list), "'t1_temperatures' must be a list."
    assert isinstance(wd, list), "'wasserstein_distances' must be a list."
    assert isinstance(pval, float) or isinstance(pval, int), "'wilcoxon_p_value' must be a float."
    assert len(t1) == 10, f"Expected 10 values for 't1_temperatures', got {len(t1)}."
    assert len(wd) == 10, f"Expected 10 values for 'wasserstein_distances', got {len(wd)}."
    assert all(isinstance(x, (float, int)) for x in t1), "All items in 't1_temperatures' must be numbers."
    assert all(isinstance(x, (float, int)) for x in wd), "All items in 'wasserstein_distances' must be numbers."


def test_analysis_results_values():
    """Validate the values inside the output JSON for correctness."""
    if not os.path.isfile(RESULT):
        pytest.skip("JSON file missing.")

    with open(RESULT, "r") as f:
        data = json.load(f)

    t1 = data.get("t1_temperatures", [])
    wd = data.get("wasserstein_distances", [])
    pval = data.get("wilcoxon_p_value", -1.0)
    expected_t1, expected_wd, expected_pval = reference_results(np.load(SIGNALS), np.load(BASELINE))

    if len(t1) == 10:
        assert math.isclose(t1[0], 1000.0, abs_tol=1.0), f"Initial T1 temperature should be 1000.0, got {t1[0]}"
        assert math.isclose(t1[-1], expected_t1[-1], abs_tol=0.5), f"Final T1 temperature at t=90 is incorrect, got {t1[-1]}"
        assert np.allclose(t1, expected_t1, rtol=1e-4, atol=0.5), "T1 temperatures do not match the ODE solution."

    if len(wd) == 10:
        assert all(w >= 0.0 for w in wd), "Wasserstein distances cannot be negative."
        assert np.allclose(wd, expected_wd, rtol=1e-4, atol=0.15), "Wasserstein distances are incorrect."

    assert 0.0 <= pval <= 1.0, f"Wilcoxon p-value must be between 0.0 and 1.0, got {pval}"
    assert math.isclose(pval, expected_pval, rel_tol=0.0, abs_tol=1e-10), "Wilcoxon p-value is incorrect."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
