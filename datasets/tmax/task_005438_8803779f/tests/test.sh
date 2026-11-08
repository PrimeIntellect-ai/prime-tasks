#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/verify_task.py
import csv
import glob
import json
import math
import os
import subprocess
import sys
import tempfile

import numpy as np
import pandas as pd

EXP_PATH = "/home/user/experiments.csv"
MET_PATH = "/home/user/metrics.json"
REPORT_PATH = "/home/user/report.json"

with open(EXP_PATH, "rb") as f:
    original_exp = f.read()
with open(MET_PATH, "rb") as f:
    original_met = f.read()

original_experiments = [
    {"run_id": 1, "model_type": "alpha", "deploy_status": "deployed"},
    {"run_id": 2, "model_type": "alpha", "deploy_status": "deployed"},
    {"run_id": 3, "model_type": "alpha", "deploy_status": "failed"},
    {"run_id": 4, "model_type": "beta", "deploy_status": "deployed"},
    {"run_id": 5, "model_type": "beta", "deploy_status": "deployed"},
    {"run_id": 7, "model_type": "beta", "deploy_status": "deployed"},
]
original_metrics = [
    {"run_id": 1, "errors_detected": 5},
    {"run_id": 2, "errors_detected": 3},
    {"run_id": 3, "errors_detected": 10},
    {"run_id": 4, "errors_detected": 2},
    {"run_id": 5, "errors_detected": 1},
    {"run_id": 6, "errors_detected": 0},
    {"run_id": 7, "errors_detected": 4},
]

probe_experiments = [
    {"run_id": 101, "model_type": "alpha", "deploy_status": "deployed"},
    {"run_id": 102, "model_type": "alpha", "deploy_status": "deployed"},
    {"run_id": 103, "model_type": "alpha", "deploy_status": "Deployed"},
    {"run_id": 104, "model_type": "beta", "deploy_status": "deployed"},
    {"run_id": 105, "model_type": "beta", "deploy_status": "deployed"},
    {"run_id": 106, "model_type": "beta", "deploy_status": "deployed"},
    {"run_id": 107, "model_type": "beta", "deploy_status": "deployed"},
    {"run_id": 108, "model_type": "beta", "deploy_status": "failed"},
    {"run_id": 110, "model_type": "beta", "deploy_status": "deployed"},
]
probe_metrics = [
    {"run_id": 101, "errors_detected": 7},
    {"run_id": 102, "errors_detected": 1},
    {"run_id": 103, "errors_detected": 100},
    {"run_id": 104, "errors_detected": 0},
    {"run_id": 105, "errors_detected": 3},
    {"run_id": 106, "errors_detected": 8},
    {"run_id": 107, "errors_detected": 11},
    {"run_id": 108, "errors_detected": 99},
    {"run_id": 109, "errors_detected": 50},
    {"run_id": 110, "errors_detected": None},
]


def write_fixture(experiments, metrics):
    with open(EXP_PATH, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=["run_id", "model_type", "deploy_status"])
        writer.writeheader()
        writer.writerows(experiments)
    with open(MET_PATH, "w") as f:
        json.dump(metrics, f)


def expected_report(experiments, metrics):
    exp = pd.DataFrame(experiments)
    met = pd.DataFrame(metrics)
    joined = met.merge(exp, on="run_id", how="left")
    filtered = joined[joined["deploy_status"] == "deployed"].dropna(
        subset=["deploy_status", "errors_detected"]
    ).copy()
    filtered["errors_detected"] = filtered["errors_detected"].astype(int)

    beta = filtered.loc[filtered["model_type"] == "beta", "errors_detected"].to_numpy()
    np.random.seed(42)
    means = np.array([
        np.random.choice(beta, size=len(beta), replace=True).mean()
        for _ in range(1000)
    ])
    lower, upper = np.percentile(means, [2.5, 97.5])

    alpha = filtered.loc[filtered["model_type"] == "alpha", "errors_detected"]
    posterior = (2.0 + float(alpha.sum())) / (1.0 + len(alpha))
    return {
        "bootstrap_lower": float(lower),
        "bootstrap_upper": float(upper),
        "posterior_mean": float(posterior),
    }


runner_source = r'''
import inspect
import json
import os
import runpy
import sys
import numpy as np
import pandas as pd

script = os.path.abspath(sys.argv[1])
trace_path = sys.argv[2]
trace = {"seed_calls": [], "percentile_calls": [], "integer_errors_seen": False}
orig_seed = np.random.seed
orig_percentile = np.percentile

def tracked_seed(value=None, *args, **kwargs):
    if isinstance(value, np.generic):
        value = value.item()
    trace["seed_calls"].append(value)
    return orig_seed(value, *args, **kwargs)

def has_integer_errors(frame):
    if os.path.abspath(frame.f_code.co_filename) != script:
        return False
    for value in frame.f_locals.values():
        try:
            if isinstance(value, pd.DataFrame) and "errors_detected" in value.columns:
                if pd.api.types.is_integer_dtype(value["errors_detected"].dtype):
                    return True
            if isinstance(value, pd.Series):
                if value.name == "errors_detected" and pd.api.types.is_integer_dtype(value.dtype):
                    return True
            if isinstance(value, np.ndarray) and value.size and value.size < 1000:
                if np.issubdtype(value.dtype, np.integer):
                    return True
        except Exception:
            pass
    return False

def tracked_percentile(a, q, *args, **kwargs):
    try:
        q_values = np.asarray(q).reshape(-1).astype(float).tolist()
    except Exception:
        q_values = []
    try:
        sample_count = int(np.asarray(a).size)
    except Exception:
        sample_count = -1
    trace["percentile_calls"].append({"q": q_values, "sample_count": sample_count})
    frame = inspect.currentframe().f_back
    while frame is not None:
        if has_integer_errors(frame):
            trace["integer_errors_seen"] = True
            break
        frame = frame.f_back
    return orig_percentile(a, q, *args, **kwargs)

np.random.seed = tracked_seed
np.percentile = tracked_percentile
status = 0
try:
    runpy.run_path(script, run_name="__main__")
except SystemExit as e:
    if e.code not in (None, 0):
        status = 1
except BaseException:
    status = 1
finally:
    with open(trace_path, "w") as f:
        json.dump(trace, f)
sys.exit(status)
'''
with open("/tmp/run_candidate.py", "w") as f:
    f.write(runner_source)


def load_and_validate_report(expected, original_case=False):
    assert os.path.exists(REPORT_PATH), f"Expected output file {REPORT_PATH} is missing."
    assert os.path.isfile(REPORT_PATH), f"{REPORT_PATH} is not a file."
    with open(REPORT_PATH) as f:
        report = json.load(f)

    expected_keys = {"bootstrap_lower", "bootstrap_upper", "posterior_mean"}
    assert isinstance(report, dict), "The JSON output must be a dictionary."
    missing = expected_keys - set(report)
    assert not missing, f"The JSON output is missing keys: {missing}"
    for key in expected_keys:
        assert isinstance(report[key], (int, float)) and not isinstance(report[key], bool), \
            f"Value for {key} must be a float."
        assert math.isfinite(float(report[key])), f"Value for {key} must be finite."
        assert math.isclose(float(report[key]), expected[key], rel_tol=1e-10, abs_tol=1e-10), \
            f"Incorrect {key}: expected {expected[key]}, got {report[key]}"

    if original_case:
        expected_posterior_mean = 10.0 / 3.0
        assert math.isclose(float(report["posterior_mean"]), expected_posterior_mean, rel_tol=1e-5)
        lower = float(report["bootstrap_lower"])
        upper = float(report["bootstrap_upper"])
        assert 1.0 <= lower <= 4.0
        assert 1.0 <= upper <= 4.0
        assert lower < upper
        assert 1.0 <= lower <= 2.0
        assert 2.6 <= upper <= 4.0


def run_case(script, experiments, metrics, original_case=False):
    write_fixture(experiments, metrics)
    try:
        os.remove(REPORT_PATH)
    except FileNotFoundError:
        pass
    fd, trace_path = tempfile.mkstemp(prefix="trace_", suffix=".json")
    os.close(fd)
    try:
        result = subprocess.run(
            [sys.executable, "/tmp/run_candidate.py", script, trace_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
            text=True,
        )
        assert result.returncode == 0, result.stderr[-2000:]
        expected = expected_report(experiments, metrics)
        load_and_validate_report(expected, original_case=original_case)
        with open(trace_path) as f:
            trace = json.load(f)
        assert trace.get("seed_calls") == [42], \
            "The script must call numpy.random.seed(42) exactly once before bootstrapping."
        calls = trace.get("percentile_calls", [])
        qs = [q for call in calls for q in call.get("q", [])]
        assert 2.5 in qs and 97.5 in qs, "The script must use numpy.percentile at 2.5 and 97.5."
        relevant = [call for call in calls if 2.5 in call.get("q", []) or 97.5 in call.get("q", [])]
        assert relevant and all(call.get("sample_count") == 1000 for call in relevant), \
            "Percentiles must be calculated from exactly 1000 bootstrap means."
        assert trace.get("integer_errors_seen") is True, \
            "errors_detected must be converted to an integer dtype before analysis."
    finally:
        try:
            os.remove(trace_path)
        except FileNotFoundError:
            pass


roots = ["/home/user", "/tmp", "/root", "/workspace"]
candidates = []
for root in roots:
    if os.path.isdir(root):
        for path in glob.glob(os.path.join(root, "**", "*.py"), recursive=True):
            real = os.path.realpath(path)
            if real in {"/tmp/verify_task.py", "/tmp/run_candidate.py"}:
                continue
            if real.startswith("/tests/") or real.startswith("/usr/"):
                continue
            if os.path.isfile(real) and real not in candidates:
                candidates.append(real)

assert candidates, "No Python script was written."
passed = False
errors = []
try:
    for candidate in candidates:
        try:
            run_case(candidate, original_experiments, original_metrics, original_case=True)
            run_case(candidate, probe_experiments, probe_metrics, original_case=False)
            passed = True
            break
        except Exception as e:
            errors.append(f"{candidate}: {e}")
    assert passed, "No written Python script correctly performs the required processing. " + " | ".join(errors[-5:])
finally:
    with open(EXP_PATH, "wb") as f:
        f.write(original_exp)
    with open(MET_PATH, "wb") as f:
        f.write(original_met)

print("verification passed")
PY_EOF

if python3 /tmp/verify_task.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
