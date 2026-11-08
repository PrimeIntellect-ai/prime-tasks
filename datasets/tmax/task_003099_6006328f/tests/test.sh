#!/bin/bash
set -e
mkdir -p /logs/verifier

rm -rf /tmp/benchmark_verifier_hook
mkdir -p /tmp/benchmark_verifier_hook

cat << 'HOOK_EOF' > /tmp/benchmark_verifier_hook/sitecustomize.py
import hashlib
import json
import os
import time
import numpy as np

_LOG = os.environ.get("BENCHMARK_CALL_LOG")

def _write(event):
    if _LOG:
        with open(_LOG, "a", encoding="utf-8") as f:
            f.write(json.dumps(event, sort_keys=True) + "\n")

try:
    from sklearn.decomposition import PCA

    _original_fit_transform = PCA.fit_transform
    _original_inverse_transform = PCA.inverse_transform

    def _fingerprint(data):
        arr = np.ascontiguousarray(np.asarray(data))
        return hashlib.sha256(arr.tobytes()).hexdigest()

    def checked_fit_transform(self, X, *args, **kwargs):
        started = time.perf_counter()
        result = _original_fit_transform(self, X, *args, **kwargs)
        duration = time.perf_counter() - started
        arr = np.asarray(X)
        _write({
            "method": "fit_transform",
            "shape": list(arr.shape),
            "dtype": str(arr.dtype),
            "sha256": _fingerprint(X),
            "duration": duration,
            "n_components": self.n_components,
            "svd_solver": self.svd_solver,
            "random_state": self.random_state,
        })
        return result

    def checked_inverse_transform(self, X, *args, **kwargs):
        started = time.perf_counter()
        result = _original_inverse_transform(self, X, *args, **kwargs)
        duration = time.perf_counter() - started
        arr = np.asarray(X)
        _write({
            "method": "inverse_transform",
            "shape": list(arr.shape),
            "dtype": str(arr.dtype),
            "duration": duration,
            "n_components": self.n_components,
            "svd_solver": self.svd_solver,
            "random_state": self.random_state,
        })
        return result

    PCA.fit_transform = checked_fit_transform
    PCA.inverse_transform = checked_inverse_transform
except Exception as exc:
    _write({"method": "hook_error", "error": repr(exc)})
HOOK_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import math
import os
import subprocess
import sys

import numpy as np
import pandas as pd
import pytest
from sklearn.decomposition import PCA
from sklearn.metrics import mean_squared_error

REPORT = '/home/user/report.json'
SCRIPT = '/home/user/benchmark.py'
CALL_LOG = '/tmp/benchmark_pca_calls.jsonl'


def fingerprint(data):
    arr = np.ascontiguousarray(np.asarray(data))
    return hashlib.sha256(arr.tobytes()).hexdigest()


@pytest.fixture(scope='session', autouse=True)
def execute_and_validate_artifact():
    assert os.path.isfile(SCRIPT), "/home/user/benchmark.py is missing"
    assert os.path.getsize(SCRIPT) > 0, "/home/user/benchmark.py is empty"

    for path in (REPORT, CALL_LOG):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    env = os.environ.copy()
    env['PYTHONPATH'] = '/tmp/benchmark_verifier_hook' + (
        os.pathsep + env['PYTHONPATH'] if env.get('PYTHONPATH') else ''
    )
    env['BENCHMARK_CALL_LOG'] = CALL_LOG

    try:
        result = subprocess.run(
            [sys.executable, SCRIPT],
            cwd='/home/user',
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=1200,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("benchmark.py did not finish within 1200 seconds")

    assert result.returncode == 0, (
        "benchmark.py failed when executed:\n"
        + result.stdout + "\n" + result.stderr
    )
    assert os.path.isfile(REPORT), "/home/user/report.json is missing after running benchmark.py"
    assert os.path.isfile(CALL_LOG), "No instrumented PCA calls were recorded"

    with open(CALL_LOG, 'r', encoding='utf-8') as f:
        events = [json.loads(line) for line in f if line.strip()]
    assert events, "No PCA operations were recorded"
    assert not any(e.get('method') == 'hook_error' for e in events), "PCA instrumentation failed"

    data_a = pd.read_csv('/home/user/data_A.csv')
    data_b = pd.read_csv('/home/user/data_B.csv')
    pipeline1 = data_a.merge(data_b, on='id', how='left').dropna().drop(columns=['id'])
    pipeline2 = data_a.merge(data_b, on='id', how='inner').drop(columns=['id'])

    expected = {
        'float64': fingerprint(pipeline1),
        'int64': fingerprint(pipeline2),
    }

    fit_events = [e for e in events if e.get('method') == 'fit_transform']
    inverse_events = [e for e in events if e.get('method') == 'inverse_transform']

    for dtype in ('float64', 'int64'):
        calls = [e for e in fit_events if e.get('dtype') == dtype]
        # Exactly 100 benchmark calls plus the fit_transform required for reconstruction.
        assert len(calls) == 101, f"Expected 101 fit_transform calls for {dtype}, got {len(calls)}"
        assert all(e.get('shape') == [9000, 100] for e in calls), "PCA received data with the wrong shape"
        assert all(e.get('sha256') == expected[dtype] for e in calls), "PCA did not receive the CSV-derived pipeline data"
        assert all(e.get('n_components') == 5 for e in calls), "PCA n_components must be 5"
        assert all(e.get('svd_solver') == 'full' for e in calls), "PCA svd_solver must be 'full'"
        assert all(e.get('random_state') == 42 for e in calls), "PCA random_state must be 42"
        assert all(math.isfinite(e['duration']) and e['duration'] > 0 for e in calls)

    assert len(inverse_events) == 2, f"Expected two inverse_transform calls, got {len(inverse_events)}"
    assert all(e.get('shape') == [9000, 5] for e in inverse_events)
    assert all(e.get('n_components') == 5 for e in inverse_events)
    assert all(e.get('svd_solver') == 'full' for e in inverse_events)
    assert all(e.get('random_state') == 42 for e in inverse_events)

    with open(REPORT, 'r', encoding='utf-8') as f:
        report = json.load(f)

    expected_mses = {}
    for name, frame in (('pipeline1_mse', pipeline1), ('pipeline2_mse', pipeline2)):
        pca = PCA(n_components=5, svd_solver='full', random_state=42)
        reconstruction = pca.inverse_transform(pca.fit_transform(frame))
        expected_mses[name] = float(mean_squared_error(frame, reconstruction))
        assert math.isclose(report[name], expected_mses[name], rel_tol=1e-7, abs_tol=1e-5), (
            f"{name} was not computed from the required pipeline and PCA reconstruction"
        )

    # Remove the one fit_transform associated with each reconstruction call; the
    # remaining 100 calls are the timed benchmark iterations.
    reconstruction_fit_indexes = set()
    for inverse_index, event in enumerate(events):
        if event.get('method') == 'inverse_transform':
            previous = inverse_index - 1
            assert previous >= 0 and events[previous].get('method') == 'fit_transform', (
                "inverse_transform was not applied to a fresh fit_transform result"
            )
            reconstruction_fit_indexes.add(previous)

    timed = {'float64': [], 'int64': []}
    for index, event in enumerate(events):
        if event.get('method') == 'fit_transform' and index not in reconstruction_fit_indexes:
            if event.get('dtype') in timed:
                timed[event['dtype']].append(event['duration'])

    for dtype, report_key in (
        ('float64', 'pipeline1_avg_time'),
        ('int64', 'pipeline2_avg_time'),
    ):
        assert len(timed[dtype]) == 100, f"Expected exactly 100 timed PCA calls for {dtype}"
        observed_average = sum(timed[dtype]) / 100.0
        reported_average = report[report_key]
        assert math.isfinite(reported_average) and reported_average > 0
        # The script's outer timer includes Python and verifier-hook overhead, so
        # allow a modest envelope around time spent inside fit_transform itself.
        assert reported_average >= observed_average * 0.75
        assert reported_average <= observed_average * 3.0 + 0.02, (
            f"{report_key} is inconsistent with the measured PCA executions"
        )


def test_report_json_exists():
    assert os.path.isfile('/home/user/report.json'), "/home/user/report.json is missing"


def test_report_json_content():
    with open('/home/user/report.json', 'r') as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            assert False, "/home/user/report.json is not a valid JSON file"

    expected_keys = [
        "rows_remaining",
        "pipeline1_dtype",
        "pipeline2_dtype",
        "pipeline1_mse",
        "pipeline2_mse",
        "pipeline1_avg_time",
        "pipeline2_avg_time"
    ]

    for key in expected_keys:
        assert key in report, f"Key '{key}' is missing in report.json"

    assert report["rows_remaining"] == 9000, f"Expected rows_remaining to be 9000, got {report['rows_remaining']}"
    assert report["pipeline1_dtype"] == "float64", f"Expected pipeline1_dtype to be 'float64', got {report['pipeline1_dtype']}"
    assert report["pipeline2_dtype"] == "int64", f"Expected pipeline2_dtype to be 'int64', got {report['pipeline2_dtype']}"

    assert isinstance(report["pipeline1_mse"], float), "pipeline1_mse must be a float"
    assert isinstance(report["pipeline2_mse"], float), "pipeline2_mse must be a float"
    assert isinstance(report["pipeline1_avg_time"], float), "pipeline1_avg_time must be a float"
    assert isinstance(report["pipeline2_avg_time"], float), "pipeline2_avg_time must be a float"

    assert report["pipeline1_mse"] > 0, "pipeline1_mse should be greater than 0"
    assert report["pipeline2_mse"] > 0, "pipeline2_mse should be greater than 0"

    mse_diff = abs(report["pipeline1_mse"] - report["pipeline2_mse"])
    assert mse_diff < 1e-5, f"MSEs should be very close, but difference is {mse_diff}"


def test_benchmark_script_exists():
    assert os.path.isfile('/home/user/benchmark.py'), "/home/user/benchmark.py is missing"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
