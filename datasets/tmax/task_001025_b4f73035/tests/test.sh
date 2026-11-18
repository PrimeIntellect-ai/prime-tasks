#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import ast
import runpy
from types import SimpleNamespace

import numpy as np
import pytest
import scipy.integrate
import emcee
import multiprocessing

SCRIPT_PATH = "/home/user/mcmc_mutations.py"
SUMMARY_PATH = "/home/user/posterior_summary.json"


def test_script_executes_required_work(monkeypatch):
    raw = np.genfromtxt("/home/user/sequence_data.csv", delimiter=",", names=True)
    data_times = np.asarray(raw["time"], dtype=float)
    observations = np.asarray(raw["mutation_load"], dtype=float)

    rng = np.random.default_rng()
    chain = np.empty((500, 50, 3), dtype=float)
    chain[:100, :, 0] = 0.90 + rng.normal(0, 0.005, (100, 50))
    chain[:100, :, 1] = 900.0 + rng.normal(0, 2.0, (100, 50))
    chain[:100, :, 2] = 0.35 + rng.normal(0, 0.003, (100, 50))

    posterior_center = np.array([
        rng.uniform(0.42, 0.58),
        rng.uniform(450.0, 550.0),
        rng.uniform(0.06, 0.18),
    ])
    chain[100:, :, 0] = posterior_center[0] + rng.normal(0, 0.004, (400, 50))
    chain[100:, :, 1] = posterior_center[1] + rng.normal(0, 1.5, (400, 50))
    chain[100:, :, 2] = posterior_center[2] + rng.normal(0, 0.002, (400, 50))

    expected_means = np.mean(chain[100:].reshape(-1, 3), axis=0)
    expected_json = {
        "r_mean": round(float(expected_means[0]), 3),
        "K_mean": round(float(expected_means[1]), 3),
        "d_mean": round(float(expected_means[2]), 3),
    }

    solver_state = {"mode": 0, "calls": []}

    def fake_solve_ivp(fun, t_span, y0, *args, **kwargs):
        method = kwargs.get("method")
        solver_state["calls"].append(method)
        assert method == "RK45", "solve_ivp must be called with method='RK45'"

        offset = 0.0 if solver_state["mode"] == 0 else 5.0
        t_eval = kwargs.get("t_eval")
        if t_eval is None:
            result_t = np.asarray([t_span[0], t_span[1]], dtype=float)
        else:
            result_t = np.asarray(t_eval, dtype=float)

        values = np.interp(result_t, data_times, observations) + offset

        def dense_solution(query_times):
            query_times = np.asarray(query_times, dtype=float)
            return np.asarray([np.interp(query_times, data_times, observations) + offset])

        return SimpleNamespace(
            success=True,
            status=0,
            message="success",
            t=result_t,
            y=np.asarray([values]),
            sol=dense_solution,
        )

    pool_instances = []

    class FakePool:
        def __init__(self, processes=None, *args, **kwargs):
            self.processes = processes
            pool_instances.append(self)

        def __enter__(self):
            return self

        def __exit__(self, exc_type, exc, tb):
            return False

        def close(self):
            pass

        def join(self):
            pass

        def terminate(self):
            pass

        def map(self, func, iterable):
            return list(map(func, iterable))

    sampler_instances = []

    class FakeEnsembleSampler:
        def __init__(self, nwalkers, ndim, log_prob_fn, *args, pool=None, **kwargs):
            if pool is None and args:
                pool = args[0]
            assert nwalkers == 50, f"Expected 50 walkers, got {nwalkers}"
            assert ndim == 3, f"Expected three parameters, got {ndim}"
            assert isinstance(pool, FakePool), "A multiprocessing.Pool must be passed to EnsembleSampler"
            assert pool.processes == 4, f"Pool must use 4 processes, got {pool.processes}"
            self.log_prob_fn = log_prob_fn
            self.ran = False
            sampler_instances.append(self)

        def run_mcmc(self, initial_state, nsteps=None, **kwargs):
            if nsteps is None:
                nsteps = kwargs.get("nsteps")
            initial_state = np.asarray(initial_state)
            assert initial_state.shape == (50, 3), f"Initial walker state has shape {initial_state.shape}"
            assert nsteps == 500, f"Expected 500 MCMC steps, got {nsteps}"

            theta = initial_state[0]
            solver_state["mode"] = 0
            before = len(solver_state["calls"])
            lp0 = self.log_prob_fn(theta)
            calls0 = solver_state["calls"][before:]
            assert calls0, "Evaluating the log probability did not call solve_ivp"

            solver_state["mode"] = 1
            before = len(solver_state["calls"])
            lp1 = self.log_prob_fn(theta)
            calls1 = solver_state["calls"][before:]
            assert calls1, "Evaluating the log probability did not call solve_ivp"
            assert np.isfinite(lp0) and np.isfinite(lp1), "Log probability was not finite on valid test inputs"
            assert not np.isclose(lp0, lp1), "The likelihood does not use the trajectory returned by solve_ivp"

            solver_state["mode"] = 0
            self.ran = True
            return None

        def get_chain(self, discard=0, thin=1, flat=False, **kwargs):
            assert self.ran, "The chain was requested before run_mcmc"
            selected = chain[discard::thin]
            if flat:
                return selected.reshape(-1, 3)
            return selected.copy()

    monkeypatch.setattr(scipy.integrate, "solve_ivp", fake_solve_ivp)
    monkeypatch.setattr(multiprocessing, "Pool", FakePool)
    monkeypatch.setattr(emcee, "EnsembleSampler", FakeEnsembleSampler)

    if os.path.exists(SUMMARY_PATH):
        os.remove(SUMMARY_PATH)

    runpy.run_path(SCRIPT_PATH, run_name="__main__")

    assert pool_instances, "The script did not create a multiprocessing.Pool"
    assert sampler_instances, "The script did not create an emcee.EnsembleSampler"
    assert os.path.isfile(SUMMARY_PATH), "Executing the script did not create posterior_summary.json"

    with open(SUMMARY_PATH, "r") as f:
        actual = json.load(f)
    assert actual == expected_json, (
        "posterior_summary.json must contain the rounded means of the executed "
        "sampler chain after discarding the first 100 steps"
    )


def test_json_exists_and_valid():
    file_path = "/home/user/posterior_summary.json"
    assert os.path.exists(file_path), f"File {file_path} does not exist. Did you run the script?"
    assert os.path.isfile(file_path), f"{file_path} is not a file."

    with open(file_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {file_path} does not contain valid JSON.")

    expected_keys = {"r_mean", "K_mean", "d_mean"}
    assert set(data.keys()) == expected_keys, f"JSON keys must be exactly {expected_keys}, found {set(data.keys())}"
    for k in expected_keys:
        assert isinstance(data[k], (int, float)), f"Value for {k} must be a number, found {type(data[k])}"


def test_json_values():
    file_path = "/home/user/posterior_summary.json"
    if not os.path.exists(file_path):
        pytest.skip("JSON file missing.")

    with open(file_path, "r") as f:
        data = json.load(f)

    r = data["r_mean"]
    K = data["K_mean"]
    d = data["d_mean"]

    assert 0.3 <= r <= 0.7, f"r_mean {r} is outside the expected range [0.3, 0.7]"
    assert 400 <= K <= 600, f"K_mean {K} is outside the expected range [400, 600]"
    assert 0.01 <= d <= 0.3, f"d_mean {d} is outside the expected range [0.01, 0.3]"


def test_script_modifications():
    file_path = "/home/user/mcmc_mutations.py"
    assert os.path.exists(file_path), f"File {file_path} does not exist."

    with open(file_path, "r") as f:
        content = f.read()

    assert "solve_ivp" in content, "The script does not seem to use scipy.integrate.solve_ivp."
    assert "RK45" in content, "The script does not seem to specify the RK45 method for solve_ivp."
    assert "multiprocessing" in content, "The script does not import or use multiprocessing."
    assert "Pool" in content, "The script does not seem to use multiprocessing.Pool."

    try:
        ast.parse(content)
    except SyntaxError:
        pytest.fail("The script contains syntax errors and cannot be parsed.")

    assert "pool=" in content or "pool =" in content or "Pool" in content, "Could not verify that pool was passed to the sampler."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
