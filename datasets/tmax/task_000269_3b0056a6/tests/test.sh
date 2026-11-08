#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import json
import math
import multiprocessing
import os
import runpy
import subprocess
import sys

import numpy as np
import pytest
import scipy.integrate

SCRIPT_PATH = "/home/user/run_diffusion.py"
JSON_PATH = "/home/user/steady_states.json"


def load_submission():
    name = "run_diffusion_submission"
    sys.modules.pop(name, None)
    spec = importlib.util.spec_from_file_location(name, SCRIPT_PATH)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def test_00_script_executes_successfully_and_quickly():
    assert os.path.isfile(SCRIPT_PATH), f"The file {SCRIPT_PATH} does not exist."
    if os.path.exists(JSON_PATH):
        os.remove(JSON_PATH)
    completed = subprocess.run(
        [sys.executable, SCRIPT_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=45,
    )
    assert completed.returncode == 0, (
        f"run_diffusion.py failed with exit code {completed.returncode}.\n"
        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )


def test_steady_states_json_exists_and_correct():
    """Test that steady_states.json exists and contains the correct analytical means."""
    assert os.path.isfile(JSON_PATH), f"The file {JSON_PATH} does not exist. Did you run the script?"

    with open(JSON_PATH, "r") as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {JSON_PATH} does not contain valid JSON.")

    expected = {
        "1": 0.4851259169604859,
        "2": 0.4891152069695679,
        "3": 0.5186938920150536,
        "4": 0.5401828519137887
    }

    for seed, expected_mean in expected.items():
        assert seed in results, f"Seed '{seed}' is missing from the JSON output."
        actual_mean = results[seed]
        assert isinstance(actual_mean, float), f"Value for seed '{seed}' should be a float."
        assert math.isclose(actual_mean, expected_mean, rel_tol=1e-9), \
            f"Mean for seed '{seed}' is incorrect. Expected {expected_mean}, got {actual_mean}."


def test_run_diffusion_script_modifications():
    """Test that the run_diffusion.py script was properly optimized and modified."""
    assert os.path.isfile(SCRIPT_PATH), f"The file {SCRIPT_PATH} does not exist."

    with open(SCRIPT_PATH, "r") as f:
        content = f.read()

    # 1. Integrator fix
    has_stiff_solver = any(method in content for method in ["method='BDF'", 'method="BDF"', "method='LSODA'", 'method="LSODA"', "method='Radau'", 'method="Radau"'])
    assert has_stiff_solver, "The script does not use a stiff solver (BDF, LSODA, or Radau) in solve_ivp."
    assert "method='RK45'" not in content and 'method="RK45"' not in content, "The script should no longer use the 'RK45' method."

    # 2. Parallelization
    assert "multiprocessing.Pool" in content or "Pool(" in content, "The script does not appear to use multiprocessing.Pool."

    # 3. Analytical Validation
    assert "assert" in content, "The script is missing an assert statement for validation."
    assert "1e-5" in content or "0.00001" in content, "The script is missing the 1e-5 tolerance check in the assert statement."


def test_simulate_graph_handles_unseen_seeds_and_really_uses_stiff_solver():
    module = load_submission()
    assert callable(getattr(module, "simulate_graph", None)), "simulate_graph is missing or not callable."

    real_solve_ivp = scipy.integrate.solve_ivp
    calls = []

    def recording_solve_ivp(*args, **kwargs):
        calls.append(kwargs.get("method"))
        return real_solve_ivp(*args, **kwargs)

    old_module_solver = getattr(module, "solve_ivp", None)
    module.solve_ivp = recording_solve_ivp
    scipy.integrate.solve_ivp = recording_solve_ivp
    try:
        for seed in (17, 29):
            key, value = module.simulate_graph(seed)
            expected = float(np.random.RandomState(seed).rand(50).mean())
            assert key == str(seed)
            assert math.isclose(float(value), expected, rel_tol=0.0, abs_tol=1e-12), (
                f"simulate_graph({seed}) did not return the analytical mean derived from its initial state."
            )
    finally:
        scipy.integrate.solve_ivp = real_solve_ivp
        if old_module_solver is not None:
            module.solve_ivp = old_module_solver

    assert len(calls) >= 2, "simulate_graph did not actually call solve_ivp for unseen seeds."
    assert all(str(method).upper() in {"BDF", "LSODA", "RADAU"} for method in calls), (
        f"simulate_graph used a non-stiff solver at runtime: {calls}"
    )


def test_validation_assertion_is_active():
    module = load_submission()
    real_solve_ivp = scipy.integrate.solve_ivp

    def biased_solve_ivp(*args, **kwargs):
        sol = real_solve_ivp(*args, **kwargs)
        sol.y[:, -1] = sol.y[:, -1] + 2e-5
        return sol

    old_module_solver = getattr(module, "solve_ivp", None)
    module.solve_ivp = biased_solve_ivp
    scipy.integrate.solve_ivp = biased_solve_ivp
    try:
        with pytest.raises(AssertionError):
            module.simulate_graph(37)
    finally:
        scipy.integrate.solve_ivp = real_solve_ivp
        if old_module_solver is not None:
            module.solve_ivp = old_module_solver


class _ImmediateResult:
    def __init__(self, value):
        self.value = value

    def get(self, timeout=None):
        return self.value


class _RecordingPool:
    instances = []

    def __init__(self, processes=None, *args, **kwargs):
        self.processes = processes
        self.submitted = []
        type(self).instances.append(self)

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc, tb):
        return False

    def close(self):
        pass

    def join(self):
        pass

    def map(self, func, iterable, chunksize=None):
        items = list(iterable)
        self.submitted.extend((func, (item,)) for item in items)
        return [func(item) for item in items]

    def imap(self, func, iterable, chunksize=1):
        return iter(self.map(func, iterable, chunksize))

    def imap_unordered(self, func, iterable, chunksize=1):
        return iter(self.map(func, iterable, chunksize))

    def starmap(self, func, iterable, chunksize=None):
        items = list(iterable)
        self.submitted.extend((func, tuple(item)) for item in items)
        return [func(*item) for item in items]

    def apply_async(self, func, args=(), kwds=None, callback=None, error_callback=None):
        kwds = {} if kwds is None else kwds
        self.submitted.append((func, tuple(args)))
        try:
            value = func(*args, **kwds)
        except Exception as exc:
            if error_callback is not None:
                error_callback(exc)
            raise
        if callback is not None:
            callback(value)
        return _ImmediateResult(value)


def test_main_uses_pool_of_four_for_all_required_seeds():
    _RecordingPool.instances = []
    real_pool = multiprocessing.Pool
    multiprocessing.Pool = _RecordingPool
    try:
        runpy.run_path(SCRIPT_PATH, run_name="__main__")
    finally:
        multiprocessing.Pool = real_pool

    pools = _RecordingPool.instances
    assert pools, "Executing the script did not construct multiprocessing.Pool."
    assert any(pool.processes == 4 for pool in pools), "multiprocessing.Pool was not configured with 4 workers."

    submitted = []
    for pool in pools:
        if pool.processes == 4:
            submitted.extend(pool.submitted)
    submitted_seeds = [args[0] for func, args in submitted if len(args) == 1 and getattr(func, "__name__", "") == "simulate_graph"]
    assert sorted(submitted_seeds) == [1, 2, 3, 4], (
        "The four-worker Pool must submit simulate_graph for seeds [1, 2, 3, 4]."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
