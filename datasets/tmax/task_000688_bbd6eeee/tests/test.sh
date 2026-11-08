#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import subprocess
import sys
import importlib.util

import numpy as np
import pytest
from sklearn.mixture import GaussianMixture

WORKSPACE_DIR = "/home/user/workspace"
NETWORK_ODE_FILE = os.path.join(WORKSPACE_DIR, "network_ode.py")
FIT_AND_COMPARE_FILE = os.path.join(WORKSPACE_DIR, "fit_and_compare.py")
FINAL_OUTPUT_FILE = os.path.join(WORKSPACE_DIR, "final_output.json")
GRAPH_FILE = os.path.join(WORKSPACE_DIR, "graph.json")
REFERENCE_FILE = os.path.join(WORKSPACE_DIR, "reference.json")


def load_network_module():
    name = "network_ode_under_test"
    sys.modules.pop(name, None)
    spec = importlib.util.spec_from_file_location(name, NETWORK_ODE_FILE)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def run_in_fresh_process(hash_seed):
    code = f'''\nimport importlib.util, json\nspec = importlib.util.spec_from_file_location("network_ode_child", {NETWORK_ODE_FILE!r})\nm = importlib.util.module_from_spec(spec)\nspec.loader.exec_module(m)\na = m.run_sim()\nprint("RESULT:" + json.dumps({{"values": a.tolist(), "sum": float(a.sum())}}))\n'''
    env = os.environ.copy()
    env["PYTHONHASHSEED"] = str(hash_seed)
    result = subprocess.run(
        [sys.executable, "-c", code], cwd=WORKSPACE_DIR, env=env,
        text=True, capture_output=True, timeout=120
    )
    assert result.returncode == 0, result.stdout + result.stderr
    lines = [line for line in result.stdout.splitlines() if line.startswith("RESULT:")]
    assert lines, "run_sim() did not return a result in a fresh Python process"
    return json.loads(lines[-1][len("RESULT:"):])


class _Term:
    def __init__(self, label):
        self.label = label

    def __mul__(self, other):
        return self

    __rmul__ = __mul__

    def __radd__(self, other):
        if other == 0:
            return _Accum([self.label])
        return NotImplemented


class _Accum:
    def __init__(self, labels):
        self.labels = labels

    def __add__(self, other):
        assert isinstance(other, _Term)
        return _Accum(self.labels + [other.label])


class _Token:
    def __init__(self, label):
        self.label = label

    def __sub__(self, other):
        return _Term(self.label)


def test_network_ode_fixed():
    assert os.path.isfile(NETWORK_ODE_FILE), f"{NETWORK_ODE_FILE} is missing."
    with open(NETWORK_ODE_FILE, "r") as f:
        content = f.read()
    # Preserve the original source-level regression assertion.
    assert "for n in set(neighbors):" not in content, "The bug in network_ode.py (iterating over an unordered set) is still present."

    module = load_network_module()
    assert callable(getattr(module, "run_sim", None)), "network_ode.py must define run_sim()."
    assert callable(getattr(module, "odefunc", None)), "network_ode.py must define odefunc()."

    # Exercise the derivative with deliberately unsorted string IDs and record
    # the actual floating-point aggregation order. Numerical or lexical sorting
    # is accepted, but the input/set iteration order is not.
    y = np.array([_Token(str(i)) for i in range(11)], dtype=object)
    derivative = module.odefunc(0.0, y, {"0": ["2", "10", "1"]})
    observed = derivative[0]
    assert isinstance(observed, _Accum), "odefunc did not aggregate neighbor contributions as expected"
    assert observed.labels in (["1", "2", "10"], ["1", "10", "2"]), (
        f"Neighbors were not aggregated in a strictly sorted order: {observed.labels}"
    )

    # Hash randomization must not affect the actual simulation result.
    first = run_in_fresh_process(101)
    second = run_in_fresh_process(907)
    assert first["sum"] == second["sum"], "run_sim() final sums differ across hash seeds"
    assert first["values"] == second["values"], "run_sim() final states differ across hash seeds"


def test_fit_and_compare_script_exists():
    assert os.path.isfile(FIT_AND_COMPARE_FILE), f"{FIT_AND_COMPARE_FILE} was not created."


def expected_report():
    module = load_network_module()
    final_a = np.asarray(module.run_sim())
    final_b = np.asarray(module.run_sim())
    deterministic = float(np.sum(final_a)) == float(np.sum(final_b))
    indices = np.flatnonzero(final_a > 0.5).reshape(-1, 1)
    assert len(indices) >= 2, "Simulation did not provide enough samples for a 2-component GMM"
    model = GaussianMixture(n_components=2, random_state=42)
    model.fit(indices)
    predicted = np.sort(model.means_.reshape(-1))
    with open(REFERENCE_FILE, "r") as f:
        reference = np.sort(np.asarray(json.load(f)["ref_means"], dtype=float))
    return deterministic, float(np.linalg.norm(predicted - reference))


def execute_fit_script():
    if os.path.exists(FINAL_OUTPUT_FILE):
        os.remove(FINAL_OUTPUT_FILE)
    result = subprocess.run(
        [sys.executable, FIT_AND_COMPARE_FILE], cwd=WORKSPACE_DIR,
        text=True, capture_output=True, timeout=120
    )
    assert result.returncode == 0, result.stdout + result.stderr
    assert os.path.isfile(FINAL_OUTPUT_FILE), f"{FINAL_OUTPUT_FILE} was not generated."
    with open(FINAL_OUTPUT_FILE, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{FINAL_OUTPUT_FILE} is not valid JSON.")


def assert_report(data, expected_deterministic, expected_error):
    # Preserve all original report assertions.
    assert "is_deterministic" in data, "Key 'is_deterministic' missing in final_output.json"
    assert data["is_deterministic"] is True, "Expected 'is_deterministic' to be true."
    assert "l2_error" in data, "Key 'l2_error' missing in final_output.json"
    assert isinstance(data["l2_error"], float), "Expected 'l2_error' to be a float."
    assert data["l2_error"] >= 0.0, "L2 error cannot be negative."

    assert expected_deterministic is True, "Independent repeated simulations were not deterministic"
    assert math.isfinite(data["l2_error"]), "l2_error must be finite"
    assert math.isclose(data["l2_error"], expected_error, rel_tol=1e-10, abs_tol=1e-10), (
        f"l2_error was {data['l2_error']}, but independent recomputation gives {expected_error}"
    )


def test_final_output_json():
    # First exercise the script on verifier-selected inputs so a prewritten
    # report or hard-coded result cannot pass.
    with open(GRAPH_FILE, "r") as f:
        original_graph = f.read()
    with open(REFERENCE_FILE, "r") as f:
        original_reference = f.read()

    challenge_graph = {str(i): [] for i in range(20)}
    challenge_reference = {"ref_means": [2.731946, 17.284153]}
    try:
        with open(GRAPH_FILE, "w") as f:
            json.dump(challenge_graph, f)
        with open(REFERENCE_FILE, "w") as f:
            json.dump(challenge_reference, f)
        challenge_expected = expected_report()
        challenge_data = execute_fit_script()
        assert_report(challenge_data, *challenge_expected)
    finally:
        with open(GRAPH_FILE, "w") as f:
            f.write(original_graph)
        with open(REFERENCE_FILE, "w") as f:
            f.write(original_reference)

    # Run again on the task's real inputs and leave the required final report.
    real_expected = expected_report()
    real_data = execute_fit_script()
    assert_report(real_data, *real_expected)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
