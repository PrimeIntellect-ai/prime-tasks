#!/bin/bash
set -e
mkdir -p /logs/verifier

mkdir -p /tmp/verifier_instrument
cat << 'PY_EOF' > /tmp/verifier_instrument/sitecustomize.py
import functools
import inspect
import json
import os

LOG = os.environ.get("ANALYZE_AUDIT_LOG")

def emit(event):
    if not LOG:
        return
    with open(LOG, "a", encoding="utf-8") as f:
        f.write(json.dumps(event, allow_nan=False) + "\n")

def scalar(value):
    try:
        import numpy as np
        arr = np.asarray(value)
        if arr.ndim == 0:
            return float(arr)
    except Exception:
        pass
    return None

try:
    import numpy as np
    _seed = np.random.seed

    @functools.wraps(_seed)
    def audited_seed(seed=None, *args, **kwargs):
        emit({"event": "numpy_seed", "seed": scalar(seed)})
        return _seed(seed, *args, **kwargs)

    np.random.seed = audited_seed
except Exception:
    pass

try:
    import arviz as az
    _az_hdi = az.hdi

    @functools.wraps(_az_hdi)
    def audited_hdi(*args, **kwargs):
        probability = kwargs.get("hdi_prob")
        if probability is None and len(args) > 1:
            probability = args[1]
        emit({"event": "hdi", "hdi_prob": scalar(probability)})
        return _az_hdi(*args, **kwargs)

    az.hdi = audited_hdi
except Exception:
    az = None
    _az_hdi = None

try:
    import pymc as pm

    def wrap_distribution(attribute, positional_parameters):
        original = getattr(pm, attribute)

        @functools.wraps(original)
        def wrapper(*args, **kwargs):
            event = {
                "event": "distribution",
                "distribution": attribute,
                "name": args[0] if args and isinstance(args[0], str) else kwargs.get("name"),
            }
            for parameter, position in positional_parameters.items():
                value = kwargs.get(parameter)
                if value is None and len(args) > position:
                    value = args[position]
                event[parameter] = scalar(value)
            if attribute == "StudentT":
                observed = kwargs.get("observed")
                if observed is not None:
                    try:
                        event["observed"] = np.asarray(observed, dtype=float).reshape(-1).tolist()
                    except Exception:
                        event["observed"] = None
            emit(event)
            return original(*args, **kwargs)

        setattr(pm, attribute, wrapper)

    wrap_distribution("Normal", {"mu": 1, "sigma": 2})
    wrap_distribution("HalfNormal", {"sigma": 1})
    wrap_distribution("Exponential", {"lam": 1})
    wrap_distribution("StudentT", {"nu": 1, "mu": 2, "sigma": 3})

    _sample = pm.sample
    try:
        _sample_signature = inspect.signature(_sample)
    except Exception:
        _sample_signature = None

    @functools.wraps(_sample)
    def audited_sample(*args, **kwargs):
        supplied = dict(kwargs)
        if _sample_signature is not None:
            try:
                supplied.update(_sample_signature.bind_partial(*args, **kwargs).arguments)
            except Exception:
                pass
        event = {"event": "sample"}
        for key in ("draws", "tune", "chains", "target_accept", "random_seed"):
            event[key] = scalar(supplied.get(key))
        emit(event)

        trace = _sample(*args, **kwargs)
        try:
            if hasattr(trace, "posterior"):
                values = np.asarray(trace.posterior["mu"], dtype=float)
            else:
                values = np.asarray(trace.get_values("mu", combine=True), dtype=float)
            interval = np.asarray(_az_hdi(values, hdi_prob=0.94), dtype=float).reshape(-1)
            emit({
                "event": "posterior_expected",
                "mu_mean": round(float(values.mean()), 3),
                "hdi_3%": round(float(interval[0]), 3),
                "hdi_97%": round(float(interval[-1]), 3),
            })
        except Exception as exc:
            emit({"event": "posterior_expected_error", "message": str(exc)})
        return trace

    pm.sample = audited_sample
    if hasattr(pm, "hdi"):
        _pm_hdi = pm.hdi

        @functools.wraps(_pm_hdi)
        def audited_pm_hdi(*args, **kwargs):
            probability = kwargs.get("hdi_prob")
            if probability is None and len(args) > 1:
                probability = args[1]
            emit({"event": "hdi", "hdi_prob": scalar(probability)})
            return _pm_hdi(*args, **kwargs)

        pm.hdi = audited_pm_hdi
except Exception:
    pass
PY_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import subprocess

import numpy as np
import pandas as pd
import pytest

ANALYZE_SCRIPT = "/home/user/analyze.py"
RESULTS_JSON = "/home/user/results.json"
SENSOR_CSV = "/home/user/sensor_data.csv"
INSTRUMENT_DIR = "/tmp/verifier_instrument"

EXPECTED_KEYS = {"mu_mean", "hdi_3%", "hdi_97%"}


def read_results():
    assert os.path.exists(RESULTS_JSON), f"The results file {RESULTS_JSON} does not exist."
    with open(RESULTS_JSON, "r", encoding="utf-8") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {RESULTS_JSON} is not valid JSON.")
    assert set(data.keys()) == EXPECTED_KEYS, (
        f"The JSON keys must be exactly {EXPECTED_KEYS}, found: {set(data.keys())}"
    )
    for key in EXPECTED_KEYS:
        assert isinstance(data[key], (int, float)) and not isinstance(data[key], bool), (
            f"The value for {key} must be a number."
        )
        assert np.isfinite(data[key]), f"The value for {key} must be finite."
    return data


def read_events(path):
    with open(path, "r", encoding="utf-8") as f:
        return [json.loads(line) for line in f if line.strip()]


def run_instrumented(log_path):
    if os.path.exists(log_path):
        os.remove(log_path)
    env = os.environ.copy()
    old_pythonpath = env.get("PYTHONPATH", "")
    env["PYTHONPATH"] = INSTRUMENT_DIR + (os.pathsep + old_pythonpath if old_pythonpath else "")
    env["ANALYZE_AUDIT_LOG"] = log_path
    result = subprocess.run(
        ["python3", ANALYZE_SCRIPT], capture_output=True, text=True, env=env, timeout=1800
    )
    assert result.returncode == 0, f"Running {ANALYZE_SCRIPT} failed with error:\n{result.stderr}"
    assert os.path.exists(log_path), "The analysis produced no runtime audit log."
    return read_results(), read_events(log_path)


def assert_close(actual, expected, tolerance=1e-12):
    assert actual is not None and abs(float(actual) - float(expected)) <= tolerance


def validate_runtime(events, expected_observed, results):
    seeds = [e for e in events if e.get("event") == "numpy_seed"]
    assert any(e.get("seed") == 42.0 for e in seeds), "The script did not call NumPy's global seed with 42."

    distributions = [e for e in events if e.get("event") == "distribution"]
    normal = [e for e in distributions if e.get("distribution") == "Normal" and e.get("name") == "mu"]
    assert normal, "A PyMC Normal prior named 'mu' was not created."
    assert_close(normal[-1].get("mu"), 50)
    assert_close(normal[-1].get("sigma"), 20)

    halfnormal = [e for e in distributions if e.get("distribution") == "HalfNormal" and e.get("name") == "sigma"]
    assert halfnormal, "A PyMC HalfNormal prior named 'sigma' was not created."
    assert_close(halfnormal[-1].get("sigma"), 10)

    exponential = [e for e in distributions if e.get("distribution") == "Exponential" and e.get("name") == "nu"]
    assert exponential, "A PyMC Exponential prior named 'nu' was not created."
    assert_close(exponential[-1].get("lam"), 1 / 30)

    likelihoods = [e for e in distributions if e.get("distribution") == "StudentT"]
    assert likelihoods, "A PyMC StudentT likelihood was not created."
    observed_matches = False
    for event in likelihoods:
        observed = event.get("observed")
        if observed is not None and len(observed) == len(expected_observed):
            if np.array_equal(np.asarray(observed, dtype=float), np.asarray(expected_observed, dtype=float)):
                observed_matches = True
                break
    assert observed_matches, (
        "The StudentT likelihood was not given exactly the non-missing M-101 temperatures from the CSV."
    )

    samples = [e for e in events if e.get("event") == "sample"]
    assert samples, "PyMC sample() was not called."
    sample = samples[-1]
    assert_close(sample.get("draws"), 2000)
    assert_close(sample.get("tune"), 1000)
    assert_close(sample.get("chains"), 2)
    assert_close(sample.get("target_accept"), 0.9)
    assert_close(sample.get("random_seed"), 42)

    hdis = [e for e in events if e.get("event") == "hdi"]
    assert any(e.get("hdi_prob") is not None and abs(e["hdi_prob"] - 0.94) <= 1e-12 for e in hdis), (
        "The script did not calculate a 94% HDI with ArviZ/PyMC."
    )

    expected_events = [e for e in events if e.get("event") == "posterior_expected"]
    assert expected_events, "The verifier could not extract the sampled posterior for mu."
    expected = expected_events[-1]
    for key in EXPECTED_KEYS:
        assert results[key] == expected[key], (
            f"{key} must be the posterior-derived value rounded to 3 decimals; "
            f"found {results[key]}, expected {expected[key]}."
        )


def test_analyze_script_exists():
    assert os.path.exists(ANALYZE_SCRIPT), f"The script {ANALYZE_SCRIPT} does not exist."
    assert os.path.isfile(ANALYZE_SCRIPT), f"The path {ANALYZE_SCRIPT} is not a file."


def test_results_json_exists_and_format():
    read_results()


def test_reproducibility_pipeline_and_correctness():
    first_run_data = read_results()
    original_csv = open(SENSOR_CSV, "rb").read()
    original_results = open(RESULTS_JSON, "rb").read()

    try:
        frame = pd.read_csv(SENSOR_CSV)
        expected_original = frame.loc[
            (frame["machine_id"] == "M-101") & frame["temperature"].notna(), "temperature"
        ].to_numpy(dtype=float)

        second_run_data, events = run_instrumented("/tmp/analyze_audit_original.jsonl")
        assert first_run_data == second_run_data, (
            f"Results are not reproducible. First run: {first_run_data}, second run: {second_run_data}"
        )
        validate_runtime(events, expected_original, second_run_data)

        mu_mean = second_run_data["mu_mean"]
        hdi_3 = second_run_data["hdi_3%"]
        hdi_97 = second_run_data["hdi_97%"]
        assert 54.0 <= mu_mean <= 56.0, f"mu_mean {mu_mean} is not between 54.0 and 56.0"
        assert 53.0 <= hdi_3 <= 55.0, f"hdi_3% {hdi_3} is not between 53.0 and 55.0"
        assert 55.0 <= hdi_97 <= 57.0, f"hdi_97% {hdi_97} is not between 55.0 and 57.0"

        shifted = frame.copy()
        mask = (shifted["machine_id"] == "M-101") & shifted["temperature"].notna()
        shifted.loc[mask, "temperature"] = shifted.loc[mask, "temperature"] + 15.0
        shifted.to_csv(SENSOR_CSV, index=False)
        expected_shifted = shifted.loc[mask, "temperature"].to_numpy(dtype=float)

        shifted_results, shifted_events = run_instrumented("/tmp/analyze_audit_shifted.jsonl")
        validate_runtime(shifted_events, expected_shifted, shifted_results)
        assert shifted_results["mu_mean"] > second_run_data["mu_mean"] + 8.0, (
            "Changing the M-101 observations did not appropriately change the reported posterior mean."
        )
    finally:
        with open(SENSOR_CSV, "wb") as f:
            f.write(original_csv)
        with open(RESULTS_JSON, "wb") as f:
            f.write(original_results)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
