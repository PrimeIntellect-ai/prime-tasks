#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "numpy:numpy"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/gc_probe_sitecustomize.py
import json
import os
import numpy as np

LOG = "/tmp/gc_model_probe.json"
state = {"events": [], "kde_calls": [], "samplers": []}

def save():
    tmp = LOG + ".tmp"
    with open(tmp, "w") as f:
        json.dump(state, f, allow_nan=True)
    os.replace(tmp, LOG)

def simple(x):
    try:
        return np.asarray(x).tolist()
    except Exception:
        return repr(x)

_orig_seed = np.random.seed
_orig_uniform = np.random.uniform

def seed(value=None):
    state["events"].append({"type": "seed", "value": simple(value)})
    save()
    return _orig_seed(value)

def uniform(low=0.0, high=1.0, size=None):
    result = _orig_uniform(low, high, size)
    state["events"].append({
        "type": "uniform",
        "low": simple(low),
        "high": simple(high),
        "size": simple(size),
        "result": simple(result),
    })
    save()
    return result

np.random.seed = seed
np.random.uniform = uniform

import scipy.stats as _stats
_orig_kde = _stats.gaussian_kde

class KDEProbe:
    def __init__(self, inner, record):
        self._inner = inner
        self._record = record

    def _evaluate(self, points, method):
        values = method(points)
        pts = np.asarray(points, dtype=float)
        vals = np.asarray(values, dtype=float)
        self._record["points"] = pts.tolist()
        self._record["values"] = vals.tolist()
        if pts.ndim == 1 and vals.size:
            self._record["peak"] = float(pts[int(np.argmax(vals))])
        save()
        return values

    def __call__(self, points):
        return self._evaluate(points, self._inner(points))

    def evaluate(self, points):
        return self._evaluate(points, self._inner.evaluate)

    def pdf(self, points):
        return self._evaluate(points, self._inner.pdf)

    def logpdf(self, points):
        return self._inner.logpdf(points)

    def __getattr__(self, name):
        return getattr(self._inner, name)

def gaussian_kde(dataset, *args, **kwargs):
    record = {
        "dataset": np.asarray(dataset, dtype=float).tolist(),
        "default_scott": len(args) == 0 and kwargs.get("bw_method") is None,
    }
    state["kde_calls"].append(record)
    save()
    return KDEProbe(_orig_kde(dataset, *args, **kwargs), record)

_stats.gaussian_kde = gaussian_kde

import emcee as _emcee
_OrigSampler = _emcee.EnsembleSampler

class EnsembleSamplerProbe(_OrigSampler):
    def __init__(self, nwalkers, ndim, log_prob_fn, *args, **kwargs):
        record = {"nwalkers": int(nwalkers), "ndim": int(ndim)}
        state["events"].append({"type": "sampler_init"})
        state["samplers"].append(record)

        fn_args = kwargs.get("args")
        if fn_args is None:
            fn_args = []
        try:
            record["log_prob_inside"] = float(log_prob_fn(np.array([50.0, 5.0]), *fn_args))
            record["log_prob_outside"] = [
                float(log_prob_fn(np.array([-0.01, 5.0]), *fn_args)),
                float(log_prob_fn(np.array([100.01, 5.0]), *fn_args)),
                float(log_prob_fn(np.array([50.0, 0.09]), *fn_args)),
                float(log_prob_fn(np.array([50.0, 50.01]), *fn_args)),
            ]
        except Exception as exc:
            record["log_prob_probe_error"] = repr(exc)
        save()
        self._probe_record = record
        super().__init__(nwalkers, ndim, log_prob_fn, *args, **kwargs)

    def run_mcmc(self, initial_state, nsteps, *args, **kwargs):
        coords = getattr(initial_state, "coords", initial_state)
        self._probe_record["initial_state"] = np.asarray(coords, dtype=float).tolist()
        self._probe_record["nsteps"] = int(nsteps)
        state["events"].append({"type": "run_mcmc", "nsteps": int(nsteps)})
        save()
        result = super().run_mcmc(initial_state, nsteps, *args, **kwargs)
        chain = np.asarray(self.get_chain(discard=200, flat=True), dtype=float)
        self._probe_record["posterior_mean_after_200"] = np.mean(chain, axis=0).tolist()
        self._probe_record["chain_shape_after_200"] = list(chain.shape)
        save()
        return result

_emcee.EnsembleSampler = EnsembleSamplerProbe
PY_EOF

mkdir -p /tmp/gc_probe
cp /tmp/gc_probe_sitecustomize.py /tmp/gc_probe/sitecustomize.py

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import math
import os
import subprocess
import numpy as np
import pytest

VENV_PYTHON = "/home/user/bio_env/bin/python"
SCRIPT = "/home/user/pipeline/gc_model.py"
RESULTS = "/home/user/pipeline/results.json"
REGRESSION = "/home/user/pipeline/test_regression.py"
LEGACY = "/home/user/data/legacy_results.json"
PROBE = "/tmp/gc_model_probe.json"

def read_gc():
    values = []
    seq = []
    with open("/home/user/data/reads.fasta") as f:
        for raw in f:
            line = raw.strip()
            if line.startswith(">"):
                if seq:
                    s = "".join(seq).upper()
                    values.append((s.count("G") + s.count("C")) / len(s) * 100.0)
                    seq = []
            else:
                seq.append(line)
        if seq:
            s = "".join(seq).upper()
            values.append((s.count("G") + s.count("C")) / len(s) * 100.0)
    return np.asarray(values)

def run_regression():
    return subprocess.run(
        ["/home/user/bio_env/bin/pytest", "-q", REGRESSION],
        capture_output=True, text=True, timeout=120
    )

def test_01_virtual_environment_and_packages():
    assert os.path.exists(VENV_PYTHON), "Virtual environment Python executable not found at /home/user/bio_env/bin/python"
    result = subprocess.run(
        [VENV_PYTHON, "-c", "import Bio; import numpy; import scipy; import emcee; import pytest"],
        capture_output=True, text=True
    )
    assert result.returncode == 0, f"Failed to import required packages in the virtual environment. Error:\n{result.stderr}"

def test_02_model_script_exists_and_executes_instrumented():
    assert os.path.isfile(SCRIPT), f"Model script {SCRIPT} does not exist"
    os.unlink(PROBE) if os.path.exists(PROBE) else None
    env = os.environ.copy()
    env["PYTHONPATH"] = "/tmp/gc_probe" + (":" + env["PYTHONPATH"] if env.get("PYTHONPATH") else "")
    result = subprocess.run(
        [VENV_PYTHON, SCRIPT], capture_output=True, text=True, env=env,
        cwd="/home/user/pipeline", timeout=180
    )
    assert result.returncode == 0, f"gc_model.py failed:\n{result.stdout}\n{result.stderr}"
    assert os.path.exists(PROBE), "The model did not exercise the required scientific libraries"

def test_03_required_kde_and_mcmc_work_was_performed():
    with open(PROBE) as f:
        probe = json.load(f)
    gc = read_gc()

    assert probe["kde_calls"], "scipy.stats.gaussian_kde was not used"
    kde = probe["kde_calls"][-1]
    assert kde["default_scott"], "gaussian_kde must use its default Scott bandwidth"
    assert np.allclose(np.asarray(kde["dataset"]).reshape(-1), gc, rtol=0, atol=1e-12), "KDE was not fit to the FASTA GC percentages"
    points = np.asarray(kde.get("points", [])).reshape(-1)
    expected_grid = np.linspace(0.0, 100.0, 1000)
    assert points.shape == (1000,) and np.allclose(points, expected_grid, rtol=0, atol=1e-12), "KDE was not evaluated on 1000 evenly spaced points from 0 to 100"

    assert probe["samplers"], "emcee.EnsembleSampler was not used"
    sampler = probe["samplers"][-1]
    assert sampler["nwalkers"] == 10 and sampler["ndim"] == 2
    assert sampler.get("nsteps") == 1000, "The sampler was not run for 1000 steps"
    initial = np.asarray(sampler.get("initial_state"), dtype=float)
    assert initial.shape == (10, 2), "Expected initial positions for 10 walkers and 2 dimensions"
    assert np.all((initial[:, 0] >= 40) & (initial[:, 0] <= 60)), "Walker mu values were not initialized uniformly within [40, 60]"
    assert np.all((initial[:, 1] >= 1) & (initial[:, 1] <= 10)), "Walker sigma values were not initialized uniformly within [1, 10]"

    events = probe["events"]
    init_index = max(i for i, event in enumerate(events) if event["type"] == "sampler_init")
    preceding_seeds = [(i, e) for i, e in enumerate(events[:init_index]) if e["type"] == "seed"]
    assert preceding_seeds and preceding_seeds[-1][1]["value"] == 42, "np.random.seed(42) was not set before sampler initialization"
    seed_index = preceding_seeds[-1][0]
    uniforms = [e for e in events[seed_index + 1:] if e["type"] == "uniform"]
    def exact_bounds(event, low, high):
        return event.get("low") == low and event.get("high") == high
    scalar_bounds = any(exact_bounds(e, 40, 60) for e in uniforms) and any(exact_bounds(e, 1, 10) for e in uniforms)
    vector_bounds = any(e.get("low") == [40, 1] and e.get("high") == [60, 10] for e in uniforms)
    assert scalar_bounds or vector_bounds, "Walker positions were not generated with np.random.uniform using the specified bounds"

    assert "log_prob_probe_error" not in sampler, sampler.get("log_prob_probe_error")
    assert all(math.isinf(x) and x < 0 for x in sampler["log_prob_outside"]), "Uniform priors must return -infinity outside the stated bounds"
    expected_ll = -0.5 * np.sum(((gc - 50.0) / 5.0) ** 2 + np.log(2.0 * np.pi * 25.0))
    assert abs(sampler["log_prob_inside"] - expected_ll) < 1e-7, "Log-probability is not the required Normal likelihood with a uniform in-bounds prior"

def test_04_results_json_exists_and_valid():
    assert os.path.exists(RESULTS), f"Results file {RESULTS} does not exist"
    with open(RESULTS) as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {RESULTS} is not valid JSON")
    for key in ("kde_peak", "mcmc_mu", "mcmc_sigma"):
        assert key in results, f"Missing '{key}' in results.json"
        assert isinstance(results[key], (int, float)) and not isinstance(results[key], bool), f"'{key}' must be a float"
        assert math.isfinite(results[key]), f"'{key}' must be finite"

def test_05_results_are_outputs_of_the_executed_models():
    with open(RESULTS) as f:
        results = json.load(f)
    with open(PROBE) as f:
        probe = json.load(f)
    kde = probe["kde_calls"][-1]
    posterior = probe["samplers"][-1]["posterior_mean_after_200"]
    assert abs(results["kde_peak"] - kde["peak"]) < 1e-10, "kde_peak is not the argmax of the evaluated KDE"
    assert abs(results["mcmc_mu"] - posterior[0]) < 1e-9, "mcmc_mu is not the mean of the posterior after discarding 200 steps"
    assert abs(results["mcmc_sigma"] - posterior[1]) < 1e-9, "mcmc_sigma is not the mean of the posterior after discarding 200 steps"

def test_06_original_numeric_expectations():
    gc = read_gc()
    emp_mu = float(np.mean(gc))
    emp_sigma = float(np.sqrt(np.mean((gc - emp_mu) ** 2)))
    with open(RESULTS) as f:
        results = json.load(f)
    assert 48.0 <= results["kde_peak"] <= 56.0, f"kde_peak {results['kde_peak']} is out of expected range."
    assert abs(results["mcmc_mu"] - emp_mu) <= 0.5, f"mcmc_mu {results['mcmc_mu']} is not within 0.5 of empirical mean {emp_mu}"
    assert abs(results["mcmc_sigma"] - emp_sigma) <= 0.5, f"mcmc_sigma {results['mcmc_sigma']} is not within 0.5 of empirical sigma {emp_sigma}"

def test_07_regression_test_exists_and_really_checks_both_values():
    assert os.path.exists(REGRESSION), f"Test file {REGRESSION} does not exist"
    with open(REGRESSION) as f:
        content = f.read()
    assert "mcmc_mu" in content and "mcmc_sigma" in content, "test_regression.py doesn't seem to check mcmc_mu and mcmc_sigma"
    assert "legacy_results.json" in content and "results.json" in content, "Regression test must read both legacy_results.json and results.json"
    assert "0.5" in content, "Regression test must use the requested absolute tolerance of 0.5"
    ast.parse(content)

    normal = run_regression()
    assert normal.returncode == 0, f"Regression tests failed. Pytest output:\n{normal.stdout}\n{normal.stderr}"

    with open(RESULTS) as f:
        original = json.load(f)
    with open(LEGACY) as f:
        legacy = json.load(f)
    try:
        for key in ("mcmc_mu", "mcmc_sigma"):
            altered = dict(original)
            altered[key] = legacy[key] + 1.0
            with open(RESULTS, "w") as f:
                json.dump(altered, f)
            check = run_regression()
            assert check.returncode != 0, f"Regression tests did not reject an out-of-tolerance {key}"
    finally:
        with open(RESULTS, "w") as f:
            json.dump(original, f)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
