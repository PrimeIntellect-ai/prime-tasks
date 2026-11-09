#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import stat
import subprocess
import sys
import tempfile

import pandas as pd
import pytest


def test_inference_time_file():
    """Verify that inference_time.txt exists and contains a valid float."""
    file_path = "/home/user/inference_time.txt"
    assert os.path.exists(file_path), f"File {file_path} is missing."
    assert os.path.isfile(file_path), f"{file_path} is not a file."

    with open(file_path, "r") as f:
        content = f.read().strip()

    assert content, f"File {file_path} is empty."

    try:
        time_val = float(content)
    except ValueError:
        pytest.fail(f"Content of {file_path} ('{content}') cannot be converted to a float.")

    assert time_val >= 0, f"Inference time in {file_path} must be non-negative."


def test_recommendations_file():
    """Verify that recommendations.csv exists and contains the correct recommendations."""
    file_path = "/home/user/recommendations.csv"
    assert os.path.exists(file_path), f"File {file_path} is missing."
    assert os.path.isfile(file_path), f"{file_path} is not a file."

    expected_rows = [
        ["original_product_id", "recommended_product_id"],
        ["p101", "p102"],
        ["p105", "p106"],
        ["p107", "p108"]
    ]

    with open(file_path, "r", newline="") as f:
        reader = csv.reader(f)
        actual_rows = list(reader)

    assert actual_rows == expected_rows, f"Content of {file_path} does not match expected output.\nExpected: {expected_rows}\nActual: {actual_rows}"


def _outputs_are_correct(expected_rows, measured_elapsed):
    try:
        with open("/home/user/inference_time.txt", "r") as f:
            reported = float(f.read().strip())
    except (OSError, ValueError):
        return False

    if not math.isfinite(reported) or reported < 0:
        return False

    # A randomized delay is inserted inside the actual transform call. A script
    # timing that call should report approximately the independently observed
    # duration, while a hardcoded value (especially zero) will not.
    tolerance = max(0.08, measured_elapsed * 0.30)
    if abs(reported - measured_elapsed) > tolerance:
        return False

    try:
        with open("/home/user/recommendations.csv", "r", newline="") as f:
            actual_rows = list(csv.reader(f))
    except OSError:
        return False
    return actual_rows == expected_rows


def test_script_executes_loaded_vectorizer_transform_and_benchmarks_it():
    products = pd.read_csv("/home/user/products.csv")
    expected_descriptions = products["description"].astype(str).tolist()
    expected_rows = [
        ["original_product_id", "recommended_product_id"],
        ["p101", "p102"],
        ["p105", "p106"],
        ["p107", "p108"]
    ]

    candidates = []
    for root, dirs, files in os.walk("/home/user"):
        dirs[:] = [d for d in dirs if d not in {"__pycache__", ".cache", ".local"}]
        for name in files:
            if not name.endswith(".py"):
                continue
            path = os.path.join(root, name)
            try:
                mode = os.lstat(path).st_mode
            except OSError:
                continue
            if stat.S_ISREG(mode):
                candidates.append(path)

    assert candidates, "No regular Python workflow script was left under /home/user."

    with tempfile.TemporaryDirectory(prefix="workflow_probe_") as probe_dir:
        trace_path = os.path.join(probe_dir, "trace.jsonl")
        sitecustomize = r'''
import builtins
import io
import json
import os
import pickle
import time

_TRACE = os.environ["WORKFLOW_TRACE"]
_DELAY = float(os.environ["WORKFLOW_DELAY"])
_MODEL = os.path.realpath("/home/user/vectorizer.pkl")
_loaded_ids = set()
_orig_open = builtins.open
_orig_io_open = io.open
_orig_pickle_load = pickle.load


def _name(value):
    value = getattr(value, "name", value)
    try:
        return os.path.realpath(os.fspath(value))
    except (TypeError, ValueError):
        return None


def _pickle_load(file_obj, *args, **kwargs):
    obj = _orig_pickle_load(file_obj, *args, **kwargs)
    if _name(file_obj) == _MODEL:
        _loaded_ids.add(id(obj))
    return obj

pickle.load = _pickle_load

try:
    import joblib
    _orig_joblib_load = joblib.load
    def _joblib_load(filename, *args, **kwargs):
        obj = _orig_joblib_load(filename, *args, **kwargs)
        if _name(filename) == _MODEL:
            _loaded_ids.add(id(obj))
        return obj
    joblib.load = _joblib_load
except Exception:
    pass

from sklearn.feature_extraction.text import TfidfVectorizer
_orig_transform = TfidfVectorizer.transform


def _transform(self, raw_documents, *args, **kwargs):
    documents = list(raw_documents)
    if id(self) not in _loaded_ids:
        return _orig_transform(self, documents, *args, **kwargs)
    started = time.perf_counter()
    time.sleep(_DELAY)
    result = _orig_transform(self, documents, *args, **kwargs)
    elapsed = time.perf_counter() - started
    event = {"documents": [str(x) for x in documents], "elapsed": elapsed}
    with _orig_open(_TRACE, "a", encoding="utf-8") as f:
        f.write(json.dumps(event) + "\n")
    return result

TfidfVectorizer.transform = _transform
'''
        with open(os.path.join(probe_dir, "sitecustomize.py"), "w") as f:
            f.write(sitecustomize)

        delay = 0.18 + (int.from_bytes(os.urandom(2), "big") / 65535.0) * 0.20
        failures = []
        for script in sorted(candidates):
            for output in ("/home/user/inference_time.txt", "/home/user/recommendations.csv", trace_path):
                try:
                    os.remove(output)
                except FileNotFoundError:
                    pass

            env = os.environ.copy()
            old_pythonpath = env.get("PYTHONPATH", "")
            env["PYTHONPATH"] = probe_dir + (os.pathsep + old_pythonpath if old_pythonpath else "")
            env["WORKFLOW_TRACE"] = trace_path
            env["WORKFLOW_DELAY"] = repr(delay)

            try:
                result = subprocess.run(
                    [sys.executable, script],
                    cwd="/home/user",
                    env=env,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    timeout=30,
                )
            except subprocess.TimeoutExpired:
                failures.append(f"{script}: timed out")
                continue

            if result.returncode != 0:
                failures.append(f"{script}: exited with status {result.returncode}")
                continue

            events = []
            try:
                with open(trace_path, "r") as f:
                    events = [json.loads(line) for line in f if line.strip()]
            except OSError:
                pass

            matching = [e for e in events if e.get("documents") == expected_descriptions]
            for event in matching:
                if _outputs_are_correct(expected_rows, float(event["elapsed"])):
                    return

            failures.append(f"{script}: did not load vectorizer.pkl, transform all descriptions, and report the measured call time")

    pytest.fail("No workflow script satisfied the required inference workflow. " + "; ".join(failures))
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
