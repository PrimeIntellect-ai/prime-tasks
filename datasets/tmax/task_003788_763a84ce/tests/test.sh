#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import subprocess
import sys
import textwrap

import pytest

SCRIPT_PATH = "/home/user/fit_model.py"
JSON_PATH = "/home/user/map_estimates.json"


def test_map_estimates_file():
    assert os.path.isfile(JSON_PATH), f"Expected JSON file at {JSON_PATH} is missing."

    with open(JSON_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {JSON_PATH} is not valid JSON.")

    assert "k" in data, "Key 'k' is missing from the JSON file."
    assert "c" in data, "Key 'c' is missing from the JSON file."

    k_val = data["k"]
    c_val = data["c"]
    assert isinstance(k_val, (int, float)) and not isinstance(k_val, bool), "'k' value must be a number."
    assert isinstance(c_val, (int, float)) and not isinstance(c_val, bool), "'c' value must be a number."
    assert math.isfinite(k_val), "'k' value must be finite."
    assert math.isfinite(c_val), "'c' value must be finite."
    assert 4.5 <= k_val <= 5.5, f"Estimated 'k' ({k_val}) is outside the acceptable range [4.5, 5.5]."
    assert 0.3 <= c_val <= 0.7, f"Estimated 'c' ({c_val}) is outside the acceptable range [0.3, 0.7]."


def test_script_modifications():
    assert os.path.isfile(SCRIPT_PATH), f"Script file {SCRIPT_PATH} is missing."
    with open(SCRIPT_PATH, "r") as f:
        content = f.read()

    assert "pool=" in content or "Pool(" in content, "The script does not appear to use multiprocessing.Pool in the sampler."
    assert "emcee.EnsembleSampler" in content, "The script is missing emcee.EnsembleSampler."


def test_script_executes_required_work():
    harness = r'''
import json
import os
import runpy
import sys
import types
import multiprocessing

import h5py
import numpy as np

SCRIPT_PATH = "/home/user/fit_model.py"
JSON_PATH = "/home/user/map_estimates.json"

# Use an unpredictable synthetic sampler chain so a prewritten answer cannot pass.
rng = np.random.default_rng()
center = np.array([rng.uniform(4.9, 5.1), rng.uniform(0.45, 0.55)])
post = center + rng.normal(0.0, [0.025, 0.012], size=(32, 1500, 2))
burn = np.empty((32, 500, 2), dtype=float)
burn[:, :, 0] = center[0] + 2.0
burn[:, :, 1] = center[1] + 1.0
legacy_chain = np.concatenate([burn, post], axis=1)
expected = np.median(post.reshape(-1, 2), axis=0)

state = {"pools": [], "samplers": [], "run_calls": []}

class RecordingPool:
    def __init__(self, processes=None, *args, **kwargs):
        self.processes = processes
        self.closed = False
        state["pools"].append(self)
    def __enter__(self):
        return self
    def __exit__(self, exc_type, exc, tb):
        self.close()
        return False
    def close(self):
        self.closed = True
    def join(self):
        pass
    def terminate(self):
        self.closed = True
    def map(self, func, iterable, chunksize=None):
        return list(map(func, iterable))

multiprocessing.Pool = RecordingPool

class FakeSampler:
    def __init__(self, nwalkers, ndim, log_prob_fn, *positional, **kwargs):
        self.nwalkers = nwalkers
        self.ndim = ndim
        self.log_prob_fn = log_prob_fn
        self.args = kwargs.get("args", ())
        self.pool = kwargs.get("pool", None)
        self.chain = None
        state["samplers"].append(self)

    def run_mcmc(self, initial_state, nsteps, *args, **kwargs):
        initial_state = np.asarray(initial_state)
        state["run_calls"].append((initial_state.copy(), nsteps))
        self.chain = legacy_chain.copy()
        return initial_state

    def get_chain(self, discard=0, thin=1, flat=False, **kwargs):
        # emcee's public format is (steps, walkers, dimensions).
        arr = self.chain.transpose(1, 0, 2)[discard::thin]
        return arr.reshape(-1, arr.shape[-1]) if flat else arr

fake_emcee = types.ModuleType("emcee")
fake_emcee.EnsembleSampler = FakeSampler
sys.modules["emcee"] = fake_emcee

if os.path.exists(JSON_PATH):
    os.remove(JSON_PATH)

namespace = runpy.run_path(SCRIPT_PATH, run_name="__main__")

assert len(state["pools"]) == 1, "The executed script must create one multiprocessing Pool."
pool = state["pools"][0]
assert pool.processes == 4, f"The Pool must use exactly 4 processes, got {pool.processes!r}."
assert len(state["samplers"]) == 1, "The executed script must create one emcee EnsembleSampler."
sampler = state["samplers"][0]
assert sampler.nwalkers == 32, f"Expected 32 walkers, got {sampler.nwalkers!r}."
assert sampler.ndim == 2, f"Expected two sampled parameters, got {sampler.ndim!r}."
assert sampler.pool is pool, "The four-process Pool was not passed to EnsembleSampler via pool=."
assert len(state["run_calls"]) == 1, "The sampler must be run exactly once."
initial_state, nsteps = state["run_calls"][0]
assert initial_state.shape == (32, 2), f"Initial walker array has shape {initial_state.shape}, expected (32, 2)."
assert nsteps == 2000, f"Expected a 2000-step run, got {nsteps!r}."

with h5py.File("/home/user/data.h5", "r") as f:
    expected_t = f["t"][:]
    expected_y = f["y"][:]
assert len(sampler.args) == 2, "The data arrays were not supplied to the sampler callback."
assert np.array_equal(np.asarray(sampler.args[0]), expected_t), "Sampler did not receive data.h5 time points."
assert np.array_equal(np.asarray(sampler.args[1]), expected_y), "Sampler did not receive data.h5 observations."

# Check the strict prior and that invalid proposals return before invoking model/ODE code.
assert "log_prior" in namespace and "log_probability" in namespace
log_prior = namespace["log_prior"]
log_probability = namespace["log_probability"]
for theta in [(-1.0, 1.0), (1.0, -1.0), (0.0, 1.0), (1.0, 0.0), (-1.0, -1.0)]:
    assert np.isneginf(log_prior(theta)), f"log_prior must return -inf for invalid theta={theta}."
assert np.isfinite(log_prior((1e-9, 1e-9))), "Strictly positive k and c must be allowed by the prior."

calls = {"count": 0}
def forbidden_model(theta, t):
    calls["count"] += 1
    raise AssertionError("The model/ODE was evaluated for an invalid proposal.")
log_probability.__globals__["model"] = forbidden_model
for theta in [(-1.0, 1.0), (1.0, -1.0), (0.0, 1.0), (1.0, 0.0)]:
    assert np.isneginf(log_probability(theta, expected_t, expected_y))
assert calls["count"] == 0, "Invalid proposals must be rejected before solving the ODE."

assert os.path.isfile(JSON_PATH), "Running fit_model.py did not create map_estimates.json."
with open(JSON_PATH, "r") as f:
    result = json.load(f)
assert set(result.keys()) == {"k", "c"}, "Output JSON must contain exactly the keys 'k' and 'c'."
actual = np.array([result["k"], result["c"]], dtype=float)
assert np.all(np.isfinite(actual)), "Output medians must be finite."
assert np.allclose(actual, expected, rtol=1e-10, atol=1e-10), (
    f"Output {actual.tolist()} is not the median {expected.tolist()} of the flattened chain after discarding 500 steps."
)
'''

    try:
        completed = subprocess.run(
            [sys.executable, "-c", harness],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=45,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("fit_model.py did not complete under the instrumented sampler within 45 seconds.")

    assert completed.returncode == 0, completed.stdout
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
