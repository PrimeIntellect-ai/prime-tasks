#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import subprocess
import textwrap

WORKSPACE = "/home/user/workspace"
VENV = os.path.join(WORKSPACE, "venv")
SCRIPT = os.path.join(WORKSPACE, "prepare_data.py")
RESULTS = os.path.join(WORKSPACE, "results.json")
TRACE = "/tmp/prepare_data_trace.json"


def test_workspace_and_venv_exist():
    assert os.path.isdir(WORKSPACE), f"Workspace directory {WORKSPACE} does not exist."
    assert os.path.isdir(VENV), f"Virtual environment directory {VENV} does not exist."
    assert os.path.isfile(os.path.join(VENV, "pyvenv.cfg")), "venv is not a Python virtual environment."
    venv_python = os.path.join(VENV, "bin", "python")
    assert os.path.isfile(venv_python) and os.access(venv_python, os.X_OK), "venv Python executable is missing."
    proc = subprocess.run(
        [venv_python, "-c", "import numpy, scipy"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert proc.returncode == 0, f"numpy/scipy are not usable in the venv: {proc.stderr}"


def test_script_exists():
    assert os.path.isfile(SCRIPT), f"Python script {SCRIPT} does not exist."
    assert os.path.getsize(SCRIPT) > 0, f"Python script {SCRIPT} is empty."


def test_script_performs_required_computation_and_results_are_correct():
    venv_python = os.path.join(VENV, "bin", "python")
    for path in (RESULTS, TRACE):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    harness = r'''
import inspect
import json
import math
import runpy
import numpy as np
import scipy.optimize

trace = {
    "default_rng_seeds": [],
    "rng_calls": [],
    "fsum_lengths": [],
    "minimize_calls": [],
    "percentile_calls": [],
}

_real_default_rng = np.random.default_rng
_real_fsum = math.fsum
_real_minimize = scipy.optimize.minimize
_real_percentile = np.percentile

class GeneratorProxy:
    def __init__(self, generator, seed):
        self._generator = generator
        self._seed = seed

    def normal(self, loc=0.0, scale=1.0, size=None):
        trace["rng_calls"].append({"seed": self._seed, "kind": "normal", "loc": float(loc), "scale": float(scale), "size": list(size) if isinstance(size, tuple) else size})
        return self._generator.normal(loc=loc, scale=scale, size=size)

    def standard_normal(self, size=None, dtype=float, out=None):
        trace["rng_calls"].append({"seed": self._seed, "kind": "standard_normal", "size": list(size) if isinstance(size, tuple) else size})
        return self._generator.standard_normal(size=size, dtype=dtype, out=out)

    def choice(self, a, size=None, replace=True, p=None, axis=0, shuffle=True):
        trace["rng_calls"].append({"seed": self._seed, "kind": "choice", "a": int(a) if np.isscalar(a) else None, "size": list(size) if isinstance(size, tuple) else size, "replace": bool(replace)})
        return self._generator.choice(a, size=size, replace=replace, p=p, axis=axis, shuffle=shuffle)

    def __getattr__(self, name):
        return getattr(self._generator, name)

def wrapped_default_rng(seed=None):
    trace["default_rng_seeds"].append(seed)
    return GeneratorProxy(_real_default_rng(seed), seed)

def wrapped_fsum(values):
    values = list(values)
    trace["fsum_lengths"].append(len(values))
    return _real_fsum(values)

def wrapped_minimize(fun, x0, *args, **kwargs):
    bound = inspect.signature(_real_minimize).bind_partial(fun, x0, *args, **kwargs)
    method = bound.arguments.get("method")
    probes = [np.asarray(x0, dtype=float), np.array([0.4, 1.7, -0.2]), np.array([2.1, 0.3, 0.8])]
    probe_values = [float(fun(p.copy())) for p in probes]
    trace["minimize_calls"].append({
        "x0": np.asarray(x0, dtype=float).tolist(),
        "method": method,
        "probes": [p.tolist() for p in probes],
        "probe_values": probe_values,
    })
    return _real_minimize(fun, x0, *args, **kwargs)

def wrapped_percentile(a, q, *args, **kwargs):
    trace["percentile_calls"].append({"q": np.asarray(q, dtype=float).tolist(), "size": int(np.asarray(a).size)})
    return _real_percentile(a, q, *args, **kwargs)

np.random.default_rng = wrapped_default_rng
math.fsum = wrapped_fsum
scipy.optimize.minimize = wrapped_minimize
np.percentile = wrapped_percentile

try:
    runpy.run_path("/home/user/workspace/prepare_data.py", run_name="__main__")
finally:
    with open("/tmp/prepare_data_trace.json", "w") as f:
        json.dump(trace, f)
'''
    harness_path = "/tmp/run_prepare_data_instrumented.py"
    with open(harness_path, "w") as f:
        f.write(textwrap.dedent(harness))

    proc = subprocess.run(
        [venv_python, harness_path],
        cwd=WORKSPACE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=180,
    )
    assert proc.returncode == 0, f"prepare_data.py failed when executed:\nSTDOUT:\n{proc.stdout}\nSTDERR:\n{proc.stderr}"
    assert os.path.isfile(RESULTS), f"Results file {RESULTS} was not produced by running the script."
    assert os.path.isfile(TRACE), "Execution trace was not produced."

    with open(TRACE) as f:
        trace = json.load(f)

    assert trace["default_rng_seeds"] == [42, 99], "The script must initialize exactly one RNG with seed 42 and one new bootstrap RNG with seed 99."

    noise_calls = [c for c in trace["rng_calls"] if c["seed"] == 42]
    assert len(noise_calls) == 1, "All noise must be generated in one RNG call."
    noise_call = noise_calls[0]
    assert noise_call["size"] == [1000, 100], "Noise must be generated as one (1000, 100) matrix."
    assert noise_call["kind"] in ("normal", "standard_normal"), "Noise must be normally distributed."
    if noise_call["kind"] == "normal":
        assert math.isclose(noise_call["loc"], 0.0, abs_tol=0.0)
        assert math.isclose(noise_call["scale"], 0.1, rel_tol=0.0, abs_tol=1e-15)

    boot_calls = [c for c in trace["rng_calls"] if c["seed"] == 99]
    assert len(boot_calls) == 1, "Bootstrap indices must be generated in one RNG call."
    boot_call = boot_calls[0]
    assert boot_call["kind"] == "choice"
    assert boot_call["a"] == 1000 and boot_call["size"] == [5000, 1000] and boot_call["replace"], "Bootstrap choice must draw a (5000, 1000) index matrix with replacement."

    assert trace["fsum_lengths"] == [100] * 1000, "Each of the 1000 energies must be reduced from 100 squared values using math.fsum()."
    assert len(trace["minimize_calls"]) == 1, "scipy.optimize.minimize must be called exactly once."
    minimize_call = trace["minimize_calls"][0]
    assert minimize_call["method"] == "Nelder-Mead", "Optimization method must be Nelder-Mead."
    assert minimize_call["x0"] == [1.0, 1.0, 1.0], "Optimization must start from [1.0, 1.0, 1.0]."

    import numpy as np
    from scipy.optimize import minimize

    t = np.arange(100, dtype=float) / 100.0
    frequencies = (5.0, 15.0, 30.0)
    targets = np.array([2.0, 1.0, 0.5])

    def objective(coefficients):
        x = sum(c * np.sin(2.0 * np.pi * freq * t) for c, freq in zip(coefficients, frequencies))
        fft_result = np.fft.fft(np.tanh(x))
        amplitudes = np.array([(2.0 / 100.0) * abs(fft_result[k]) for k in (5, 15, 30)])
        return float(np.sum((amplitudes - targets) ** 2))

    for probe, observed in zip(minimize_call["probes"], minimize_call["probe_values"]):
        expected = objective(np.asarray(probe, dtype=float))
        assert math.isclose(observed, expected, rel_tol=1e-10, abs_tol=1e-12), "The minimized objective is not the required FFT-amplitude SSE."

    assert len(trace["percentile_calls"]) == 1, "numpy.percentile must be used once for the confidence interval."
    percentile_call = trace["percentile_calls"][0]
    assert percentile_call["q"] == [2.5, 97.5] and percentile_call["size"] == 5000, "Percentiles must be [2.5, 97.5] over 5000 bootstrap means."

    expected_opt = minimize(objective, [1.0, 1.0, 1.0], method="Nelder-Mead")
    expected_coeffs = expected_opt.x
    base_x = sum(c * np.sin(2.0 * np.pi * freq * t) for c, freq in zip(expected_coeffs, frequencies))
    base_y = np.tanh(base_x)
    rng = np.random.default_rng(42)
    variants = base_y + rng.normal(0.0, 0.1, size=(1000, 100))
    energies = np.array([math.fsum((row * row).tolist()) for row in variants])
    rng_boot = np.random.default_rng(99)
    indices = rng_boot.choice(1000, size=(5000, 1000), replace=True)
    expected_ci = np.percentile(energies[indices].mean(axis=1), [2.5, 97.5])

    with open(RESULTS) as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as exc:
            raise AssertionError(f"File {RESULTS} is not valid JSON: {exc}")

    expected_keys = {"c1", "c2", "c3", "energy_ci_lower", "energy_ci_upper"}
    missing_keys = expected_keys - set(data.keys())
    assert not missing_keys, f"Results JSON is missing keys: {missing_keys}"
    for key in expected_keys:
        assert isinstance(data[key], (int, float)) and not isinstance(data[key], bool) and math.isfinite(data[key]), f"{key} must be a finite number."

    # Retain the original expected-range assertions.
    assert math.isclose(data["c1"], 2.668, abs_tol=1e-2), f"c1 value {data['c1']} is out of expected range."
    assert math.isclose(data["c2"], 1.353, abs_tol=1e-2), f"c2 value {data['c2']} is out of expected range."
    assert math.isclose(data["c3"], 0.613, abs_tol=1e-2), f"c3 value {data['c3']} is out of expected range."
    assert math.isclose(data["energy_ci_lower"], 62.45, abs_tol=0.1), f"energy_ci_lower {data['energy_ci_lower']} is out of expected range."
    assert math.isclose(data["energy_ci_upper"], 62.90, abs_tol=0.1), f"energy_ci_upper {data['energy_ci_upper']} is out of expected range."
    assert data["energy_ci_lower"] < data["energy_ci_upper"], "Confidence interval lower bound must be less than upper bound."

    for actual, expected in zip((data["c1"], data["c2"], data["c3"]), expected_coeffs):
        assert math.isclose(actual, float(expected), rel_tol=0.0, abs_tol=1e-8), "Reported coefficients do not match the required optimization."
    assert math.isclose(data["energy_ci_lower"], float(expected_ci[0]), rel_tol=0.0, abs_tol=1e-8), "Reported lower CI does not match the required generation and bootstrap."
    assert math.isclose(data["energy_ci_upper"], float(expected_ci[1]), rel_tol=0.0, abs_tol=1e-8), "Reported upper CI does not match the required generation and bootstrap."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
