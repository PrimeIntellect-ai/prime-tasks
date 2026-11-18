#!/bin/bash
set -e
mkdir -p /logs/verifier

rm -rf /tmp/verifier_hooks /tmp/verifier_mcmc_*.npz /tmp/verifier_minimize.jsonl
mkdir -p /tmp/verifier_hooks

cat <<'HOOK_EOF' > /tmp/verifier_hooks/sitecustomize.py
import json
import os
import numpy as np

# Instrument the required scipy optimizer before the submitted script imports it.
try:
    import scipy.optimize as _opt
    _real_minimize = _opt.minimize

    def _tracked_minimize(*args, **kwargs):
        result = _real_minimize(*args, **kwargs)
        bounds = kwargs.get("bounds", args[6] if len(args) > 6 else None)
        event = {
            "x": np.asarray(result.x, dtype=float).tolist(),
            "fun": float(result.fun),
            "has_bounds": bounds is not None,
        }
        with open("/tmp/verifier_minimize.jsonl", "a") as f:
            f.write(json.dumps(event) + "\n")
        return result

    _opt.minimize = _tracked_minimize
except Exception:
    pass

# Capture the actual chain produced by each required emcee run.
try:
    import emcee as _emcee
    _real_run_mcmc = _emcee.EnsembleSampler.run_mcmc
    _run_number = 0

    def _tracked_run_mcmc(self, initial_state, nsteps, *args, **kwargs):
        global _run_number
        try:
            initial = np.asarray(getattr(initial_state, "coords", initial_state), dtype=float)
        except Exception:
            initial = np.empty((0, 0))
        result = _real_run_mcmc(self, initial_state, nsteps, *args, **kwargs)
        chain = np.asarray(self.get_chain(), dtype=float)
        path = "/tmp/verifier_mcmc_%d.npz" % _run_number
        _run_number += 1
        np.savez(path, chain=chain, initial=initial, nsteps=int(nsteps),
                 nwalkers=int(self.nwalkers), ndim=int(self.ndim))
        return result

    _emcee.EnsembleSampler.run_mcmc = _tracked_run_mcmc
except Exception:
    pass
HOOK_EOF

cat <<'TEST_EOF' > /tmp/test_final_state.py
import csv
import glob
import json
import os
import subprocess

import numpy as np
import pandas as pd
import pytest
from scipy.optimize import minimize

SCRIPT = "/home/user/prepare_data.py"
ERROR_FILE = "/home/user/error.txt"
SAMPLES_FILE = "/home/user/posterior_samples.csv"


def objective(params, t, y):
    a, b = params
    prediction = np.exp(-a * t) * np.cos(b * t)
    return float(np.sum((y - prediction) ** 2))


@pytest.fixture(scope="session", autouse=True)
def execute_and_validate_required_work():
    assert os.path.isfile(SCRIPT), f"File {SCRIPT} is missing."
    assert not os.path.islink(SCRIPT), f"File {SCRIPT} must be a regular script."

    for path in (ERROR_FILE, SAMPLES_FILE):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    env = os.environ.copy()
    env["PYTHONPATH"] = "/tmp/verifier_hooks" + (
        os.pathsep + env["PYTHONPATH"] if env.get("PYTHONPATH") else ""
    )
    completed = subprocess.run(
        ["python3", SCRIPT], cwd="/home/user", env=env,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=180
    )
    assert completed.returncode == 0, (
        "prepare_data.py failed when executed.\nSTDOUT:\n%s\nSTDERR:\n%s"
        % (completed.stdout, completed.stderr)
    )

    data = pd.read_csv("/home/user/noisy_data.csv")
    assert list(data.columns) == ["t", "y"]
    t = data["t"].to_numpy(dtype=float)
    y = data["y"].to_numpy(dtype=float)

    # Independently derive the bounded best fit from the supplied measurements.
    fits = [
        minimize(objective, x0, args=(t, y), method="L-BFGS-B",
                 bounds=[(0.1, 2.0), (1.0, 10.0)])
        for x0 in ([0.3, 3.0], [0.8, 6.0], [1.5, 9.0])
    ]
    best = min(fits, key=lambda result: result.fun)
    assert best.success

    assert os.path.isfile(ERROR_FILE), f"File {ERROR_FILE} is missing."
    with open(ERROR_FILE) as f:
        reported_sse = float(f.read().strip())
    assert np.isfinite(reported_sse)
    assert abs(reported_sse - float(best.fun)) <= 1e-3, (
        f"Reported SSE {reported_sse} does not match the SSE independently "
        f"recomputed from noisy_data.csv ({best.fun})."
    )

    assert os.path.isfile("/tmp/verifier_minimize.jsonl"), (
        "prepare_data.py did not call scipy.optimize.minimize."
    )
    with open("/tmp/verifier_minimize.jsonl") as f:
        optimization_events = [json.loads(line) for line in f if line.strip()]
    assert optimization_events, "No scipy.optimize.minimize call was observed."
    valid_optimization = False
    for event in optimization_events:
        x = np.asarray(event["x"], dtype=float)
        if (event.get("has_bounds") and x.shape == (2,) and
                0.1 <= x[0] <= 2.0 and 1.0 <= x[1] <= 10.0 and
                objective(x, t, y) <= best.fun + 1e-3):
            valid_optimization = True
    assert valid_optimization, (
        "The observed scipy.optimize.minimize calls did not perform the required "
        "bounded best-fit optimization."
    )

    chain_files = glob.glob("/tmp/verifier_mcmc_*.npz")
    assert chain_files, "prepare_data.py did not run an emcee EnsembleSampler."

    output = pd.read_csv(SAMPLES_FILE).to_numpy(dtype=float)
    matching_chain = False
    for path in chain_files:
        record = np.load(path)
        chain = record["chain"]
        initial = record["initial"]
        nsteps = int(record["nsteps"])
        nwalkers = int(record["nwalkers"])
        ndim = int(record["ndim"])
        if nsteps < 1000 or nwalkers != 16 or ndim != 2:
            continue
        if initial.shape != (16, 2):
            continue
        if not (np.all((initial[:, 0] >= 0.1) & (initial[:, 0] <= 2.0)) and
                np.all((initial[:, 1] >= 1.0) & (initial[:, 1] <= 10.0))):
            continue
        if abs(initial[:, 0].mean() - best.x[0]) > 0.25 or abs(initial[:, 1].mean() - best.x[1]) > 0.5:
            continue
        if chain.ndim != 3 or chain.shape[1:] != (16, 2):
            continue
        flattened = chain.reshape(-1, 2)
        if len(flattened) >= 500 and output.shape == (500, 2):
            if np.allclose(output, flattened[-500:], rtol=1e-7, atol=1e-9):
                matching_chain = True
                break
    assert matching_chain, (
        "posterior_samples.csv is not the last 500 flattened samples from an "
        "observed 16-walker emcee run of at least 1000 steps."
    )

    yield


def test_error_txt_exists_and_valid():
    """Verify /home/user/error.txt exists and contains a valid SSE value."""
    file_path = "/home/user/error.txt"
    assert os.path.isfile(file_path), f"File {file_path} is missing."

    with open(file_path, "r") as f:
        content = f.read().strip()

    try:
        sse = float(content)
    except ValueError:
        pytest.fail(f"Content of {file_path} is not a valid float: {content}")

    assert 0.8 <= sse <= 1.1, f"Expected SSE to be between 0.8 and 1.1, but got {sse}"


def test_posterior_samples_exists_and_format():
    """Verify /home/user/posterior_samples.csv exists, has correct header and row count."""
    file_path = "/home/user/posterior_samples.csv"
    assert os.path.isfile(file_path), f"File {file_path} is missing."

    with open(file_path, "r", newline="") as f:
        reader = csv.reader(f)
        header = next(reader, None)
        assert header == ["a", "b"], f"Expected header ['a', 'b'], got {header}"

        rows = list(reader)
        assert len(rows) == 500, f"Expected exactly 500 data rows, but got {len(rows)}"


def test_posterior_samples_values():
    """Verify the means of the posterior samples are within the expected ranges."""
    file_path = "/home/user/posterior_samples.csv"
    assert os.path.isfile(file_path), f"File {file_path} is missing."

    a_vals = []
    b_vals = []

    with open(file_path, "r", newline="") as f:
        reader = csv.DictReader(f)
        for i, row in enumerate(reader):
            try:
                a_vals.append(float(row["a"]))
                b_vals.append(float(row["b"]))
            except (ValueError, KeyError) as e:
                pytest.fail(f"Error parsing row {i+1} in {file_path}: {e}")

    assert len(a_vals) > 0, "No data found in posterior_samples.csv"

    a_mean = sum(a_vals) / len(a_vals)
    b_mean = sum(b_vals) / len(b_vals)

    assert 0.45 <= a_mean <= 0.55, f"Mean of 'a' ({a_mean}) is outside expected range [0.45, 0.55]"
    assert 3.10 <= b_mean <= 3.18, f"Mean of 'b' ({b_mean}) is outside expected range [3.10, 3.18]"

    values = np.column_stack((a_vals, b_vals))
    assert np.isfinite(values).all(), "Posterior samples contain non-finite values."
    assert np.all((values[:, 0] >= 0.1) & (values[:, 0] <= 2.0))
    assert np.all((values[:, 1] >= 1.0) & (values[:, 1] <= 10.0))
    assert np.std(values[:, 0]) > 1e-4 and np.std(values[:, 1]) > 1e-4, (
        "Posterior samples must not all be identical."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
