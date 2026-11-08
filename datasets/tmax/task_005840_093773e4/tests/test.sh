#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import stat
import subprocess
import tempfile
import uuid

import pytest

PIPELINE = "/home/user/pipeline.sh"
BENCHMARK = "/home/user/benchmark.py"
RESULTS = "/home/user/results.json"
PLOT = "/home/user/output_plot.png"


def run_pipeline(csv_path, **kwargs):
    return subprocess.run(
        [PIPELINE, csv_path],
        capture_output=True,
        timeout=180,
        **kwargs,
    )


def test_pipeline_exists_and_executable():
    path = PIPELINE
    assert os.path.isfile(path), f"Expected pipeline script not found at {path}"
    st = os.stat(path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Pipeline script at {path} is not executable"


def test_pipeline_invalid_csv():
    path = PIPELINE
    invalid_csv = "/home/user/invalid.csv"

    result = subprocess.run([path, invalid_csv], capture_output=True, timeout=30)
    assert result.returncode == 1, f"Expected exit code 1 when running with invalid CSV, got {result.returncode}"


def test_pipeline_valid_csv():
    path = PIPELINE
    valid_csv = "/home/user/valid.csv"

    if os.path.exists(PLOT):
        os.remove(PLOT)
    if os.path.exists(RESULTS):
        os.remove(RESULTS)

    result = subprocess.run([path, valid_csv], capture_output=True, cwd="/home/user", timeout=180)
    assert result.returncode == 0, (
        f"Expected exit code 0 when running with valid CSV, got {result.returncode}. "
        f"stderr: {result.stderr.decode()}"
    )


def test_output_plot_created():
    assert os.path.isfile(PLOT), "output_plot.png was not created. Ensure matplotlib headless backend is configured properly."
    assert os.path.getsize(PLOT) > 8, "output_plot.png is empty."
    with open(PLOT, "rb") as f:
        assert f.read(8) == b"\x89PNG\r\n\x1a\n", "output_plot.png is not a valid PNG file."


def test_results_json_structure():
    assert os.path.isfile(RESULTS), f"{RESULTS} was not created."

    with open(RESULTS, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{RESULTS} does not contain valid JSON.")

    expected_keys = {"mean_threads_1", "mean_threads_4", "p_value"}
    assert set(data.keys()) == expected_keys, f"JSON keys do not match. Expected {expected_keys}, got {set(data.keys())}"

    for key in expected_keys:
        val = data[key]
        assert isinstance(val, (int, float)), f"Value for {key} should be a float, got {type(val)}"


def test_instrumented_pipeline_behavior():
    token = uuid.uuid4().hex
    work = tempfile.mkdtemp(prefix="pipeline_verify_")
    calls_path = os.path.join(work, f"calls_{token}.jsonl")
    state_path = os.path.join(work, f"state_{token}.json")
    ttest_path = os.path.join(work, f"ttest_{token}.jsonl")
    site_dir = os.path.join(work, "instrumentation")
    os.mkdir(site_dir)

    valid_csv = os.path.join(work, f"valid_{token}.csv")
    invalid_csv = os.path.join(work, f"invalid_{token}.csv")
    with open(valid_csv, "w") as f:
        f.write("id,val1,val2,label\n91,0.2,0.8,1\n92,0.7,0.1,0\n")
    with open(invalid_csv, "w") as f:
        f.write("id,val1,val2,label,extra\n91,0.2,0.8,1,x\n")

    sitecustomize = r'''import json
import os
import sys

_log = os.environ.get("PIPELINE_TTEST_LOG")
if _log and os.path.basename(sys.argv[0]) != "benchmark.py":
    try:
        import numpy as _np
        import scipy.stats as _stats
        _original = _stats.ttest_ind
        def _wrapped(a, b, *args, **kwargs):
            record = {
                "a": _np.asarray(a, dtype=float).ravel().tolist(),
                "b": _np.asarray(b, dtype=float).ravel().tolist(),
                "args": list(args),
                "kwargs": kwargs,
            }
            with open(_log, "a") as out:
                out.write(json.dumps(record) + "\n")
            return _original(a, b, *args, **kwargs)
        _stats.ttest_ind = _wrapped
    except Exception:
        pass
'''
    with open(os.path.join(site_dir, "sitecustomize.py"), "w") as f:
        f.write(sitecustomize)

    fake_benchmark = r'''import json
import os
import sys

calls_path = os.environ["PIPELINE_CALLS_LOG"]
state_path = os.environ["PIPELINE_STATE_FILE"]
record = {
    "argv": sys.argv[1:],
    "omp": os.environ.get("OMP_NUM_THREADS"),
    "backend": os.environ.get("MPLBACKEND"),
}
with open(calls_path, "a") as f:
    f.write(json.dumps(record) + "\n")

try:
    with open(state_path) as f:
        state = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    state = {"1": 0, "4": 0}

values = {
    "1": [1.0111, 1.1222, 1.2333, 1.3444, 1.4555],
    "4": [1.0222, 1.1333, 1.2444, 1.3555, 1.4668],
}
omp = os.environ.get("OMP_NUM_THREADS")
idx = state.get(omp, 0)
state[omp] = idx + 1
with open(state_path, "w") as f:
    json.dump(state, f)

with open("output_plot.png", "wb") as f:
    f.write(b"\x89PNG\r\n\x1a\nINSTRUMENTED")

if len(sys.argv) != 2 or omp not in values or idx >= len(values[omp]):
    print("unexpected benchmark invocation", file=sys.stderr)
    sys.exit(2)
print(f"Time: {values[omp][idx]:.4f}")
'''

    with open(BENCHMARK, "rb") as f:
        original_benchmark = f.read()
    original_mode = stat.S_IMODE(os.stat(BENCHMARK).st_mode)

    env = os.environ.copy()
    env["PIPELINE_CALLS_LOG"] = calls_path
    env["PIPELINE_STATE_FILE"] = state_path
    env["PIPELINE_TTEST_LOG"] = ttest_path
    env["PYTHONPATH"] = site_dir + (os.pathsep + env["PYTHONPATH"] if env.get("PYTHONPATH") else "")

    try:
        with open(BENCHMARK, "w") as f:
            f.write(fake_benchmark)
        os.chmod(BENCHMARK, original_mode)

        for artifact in (RESULTS, PLOT, calls_path, state_path, ttest_path):
            if os.path.exists(artifact):
                os.remove(artifact)

        bad = run_pipeline(invalid_csv, cwd="/home/user", env=env)
        assert bad.returncode == 1, f"A dynamically named CSV with the wrong header must exit 1, got {bad.returncode}"
        assert not os.path.exists(calls_path), "benchmark.py must not run when schema validation fails"

        result = run_pipeline(valid_csv, cwd="/home/user", env=env)
        assert result.returncode == 0, (
            f"Instrumented valid run failed with {result.returncode}. "
            f"stdout={result.stdout.decode(errors='replace')} stderr={result.stderr.decode(errors='replace')}"
        )

        with open(calls_path) as f:
            calls = [json.loads(line) for line in f if line.strip()]
        assert len(calls) == 10, f"benchmark.py must be run exactly 10 times; observed {len(calls)}"
        assert all(c["argv"] == [valid_csv] for c in calls), "Every benchmark invocation must receive the supplied CSV path"
        assert sum(c["omp"] == "1" for c in calls) == 5, "Expected exactly 5 runs with OMP_NUM_THREADS=1"
        assert sum(c["omp"] == "4" for c in calls) == 5, "Expected exactly 5 runs with OMP_NUM_THREADS=4"
        assert all((c["backend"] or "").lower() == "agg" for c in calls), "MPLBACKEND=Agg must be set for every benchmark run"

        times1 = [1.0111, 1.1222, 1.2333, 1.3444, 1.4555]
        times4 = [1.0222, 1.1333, 1.2444, 1.3555, 1.4668]

        assert os.path.isfile(ttest_path), "No call to scipy.stats.ttest_ind was observed from inline Python"
        with open(ttest_path) as f:
            ttest_calls = [json.loads(line) for line in f if line.strip()]
        matching = []
        for call in ttest_calls:
            groups = (call["a"] == times1 and call["b"] == times4) or (call["a"] == times4 and call["b"] == times1)
            if groups and call["kwargs"].get("equal_var") is False:
                matching.append(call)
        assert matching, "scipy.stats.ttest_ind must be called on the two captured timing sets with equal_var=False"

        with open(RESULTS) as f:
            data = json.load(f)
        assert set(data) == {"mean_threads_1", "mean_threads_4", "p_value"}
        for key in data:
            assert type(data[key]) is float, f"{key} must be written as a JSON float"
            assert math.isfinite(data[key]), f"{key} must be finite"

        from scipy.stats import ttest_ind
        expected = {
            "mean_threads_1": round(sum(times1) / len(times1), 4),
            "mean_threads_4": round(sum(times4) / len(times4), 4),
            "p_value": round(float(ttest_ind(times1, times4, equal_var=False).pvalue), 4),
        }
        assert data == expected, f"Results must be derived from captured timings and rounded to 4 decimals. Expected {expected}, got {data}"
    finally:
        with open(BENCHMARK, "wb") as f:
            f.write(original_benchmark)
        os.chmod(BENCHMARK, original_mode)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
