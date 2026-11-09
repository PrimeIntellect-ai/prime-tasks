#!/bin/bash
set -e
mkdir -p /logs/verifier

# Stop any API server left running by the agent so the verifier can supply
# fresh, unpredictable test data on the required endpoint.
pkill -f '/home/user/api/server.py' 2>/dev/null || true
pkill -f '/home/user/api_server.py' 2>/dev/null || true
sleep 1

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import secrets
import subprocess
import textwrap
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer

import pytest

RESULT_PATH = "/home/user/experiment_results.json"
SCRIPT_PATH = "/home/user/run_etl.py"


def test_experiment_results_exists():
    """Preserve the original check that the requested output was created."""
    assert os.path.isfile(RESULT_PATH), (
        f"Expected output file {RESULT_PATH} does not exist. "
        "Ensure the ETL script writes to this exact path."
    )


def test_experiment_results_content():
    """Preserve the original assertions for the supplied data set."""
    try:
        with open(RESULT_PATH, "r") as f:
            results = json.load(f)
    except Exception as e:
        pytest.fail(f"File {RESULT_PATH} could not be read as valid JSON. Error: {e}")

    assert "sum_projected_f1" in results, "Key 'sum_projected_f1' is missing from the JSON results."
    assert "average_posterior_mean" in results, "Key 'average_posterior_mean' is missing from the JSON results."

    expected_sum = 5.5 + 16.5
    expected_avg = ((8 / 14) + (17 / 24)) / 2
    actual_sum = results["sum_projected_f1"]
    actual_avg = results["average_posterior_mean"]

    assert isinstance(actual_sum, (int, float)), f"'sum_projected_f1' must be a number, got {type(actual_sum)}"
    assert isinstance(actual_avg, (int, float)), f"'average_posterior_mean' must be a number, got {type(actual_avg)}"
    assert math.isclose(actual_sum, expected_sum, rel_tol=1e-5, abs_tol=1e-5), (
        f"Expected sum_projected_f1 to be {expected_sum}, but got {actual_sum}. "
        "Check the join logic and linear algebra transformation."
    )
    assert math.isclose(actual_avg, expected_avg, rel_tol=1e-5, abs_tol=1e-5), (
        f"Expected average_posterior_mean to be {expected_avg}, but got {actual_avg}. "
        "Check the Bayesian inference calculation and averaging."
    )


def test_execute_pipeline_against_fresh_sources():
    assert os.path.isfile(SCRIPT_PATH), f"Required ETL script {SCRIPT_PATH} does not exist"
    assert os.path.isfile(SCRIPT_PATH) and not os.path.islink(SCRIPT_PATH), (
        f"{SCRIPT_PATH} must be a regular script, not a symlink"
    )

    # Values are selected only after the agent has finished, so a hardcoded output
    # cannot pass. The CSV also includes a missing sensor ID and unmatched rows.
    salt = secrets.randbelow(5000) + 1000
    sensor_a, sensor_b, sensor_unmatched = salt + 11, salt + 37, salt + 91
    reading_1_a = float(secrets.randbelow(70) + 3)
    reading_1_b = -float(secrets.randbelow(25) + 2)
    reading_2_a = float(secrets.randbelow(40) + 1) / 2.0
    reading_2_b = float(secrets.randbelow(55) + 2) / 3.0
    trials_a = secrets.randbelow(20) + 8
    trials_b = secrets.randbelow(30) + 12
    successes_a = secrets.randbelow(trials_a + 1)
    successes_b = secrets.randbelow(trials_b + 1)

    csv_text = (
        "sensor_id,reading_1\n"
        f"{sensor_a},{reading_1_a}\n"
        ",99999.0\n"
        f"{sensor_b},{reading_1_b}\n"
        f"{sensor_unmatched},777.0\n"
    )
    with open("/home/user/data/sensors.csv", "w") as f:
        f.write(csv_text)

    payload = [
        {"id": sensor_b, "reading_2": reading_2_b, "trials": trials_b, "successes": successes_b},
        {"id": sensor_a, "reading_2": reading_2_a, "trials": trials_a, "successes": successes_a},
        {"id": salt + 500, "reading_2": 1234.0, "trials": 9, "successes": 1},
    ]
    requests_seen = {"data": 0}

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path == "/data":
                requests_seen["data"] += 1
                body = json.dumps(payload).encode("utf-8")
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
            else:
                self.send_response(404)
                self.end_headers()

        def log_message(self, *args):
            pass

    class ReusableHTTPServer(HTTPServer):
        allow_reuse_address = True

    # Instrument normal pandas operations without changing their behavior. This
    # verifies that the missing-ID removal and explicit integer cast occur before
    # an inner join, as required by the instruction.
    hook_dir = f"/tmp/etl_verify_hook_{os.getpid()}"
    event_path = f"/tmp/etl_verify_events_{os.getpid()}"
    os.makedirs(hook_dir, mode=0o755, exist_ok=True)
    hook = r'''
import os
import pandas as pd

_event_path = os.environ.get("ETL_VERIFY_EVENTS")

def _event(name):
    if _event_path:
        with open(_event_path, "a") as f:
            f.write(name + "\\n")

def _integer_target(value):
    try:
        return bool(pd.api.types.is_integer_dtype(value))
    except Exception:
        return str(value).lower() in {"int", "int64", "int32", "int16", "int8", "int64dtype"}

_orig_series_astype = pd.Series.astype
def _series_astype(self, dtype, *args, **kwargs):
    result = _orig_series_astype(self, dtype, *args, **kwargs)
    if self.name == "sensor_id" and _integer_target(dtype):
        _event("cast")
    return result
pd.Series.astype = _series_astype

_orig_df_astype = pd.DataFrame.astype
def _df_astype(self, dtype, *args, **kwargs):
    result = _orig_df_astype(self, dtype, *args, **kwargs)
    target = dtype.get("sensor_id") if isinstance(dtype, dict) else dtype
    if "sensor_id" in self.columns and target is not None and _integer_target(target):
        _event("cast")
    return result
pd.DataFrame.astype = _df_astype

_orig_dropna = pd.DataFrame.dropna
def _dropna(self, *args, **kwargs):
    result = _orig_dropna(self, *args, **kwargs)
    subset = kwargs.get("subset")
    if "sensor_id" in self.columns and (subset is None or "sensor_id" in subset):
        _event("drop")
    return result
pd.DataFrame.dropna = _dropna

_orig_notna = pd.Series.notna
def _notna(self, *args, **kwargs):
    result = _orig_notna(self, *args, **kwargs)
    if self.name == "sensor_id":
        _event("drop")
    return result
pd.Series.notna = _notna
pd.Series.notnull = _notna

_orig_df_merge = pd.DataFrame.merge
def _df_merge(self, right, *args, **kwargs):
    left_cols = set(getattr(self, "columns", []))
    right_cols = set(getattr(right, "columns", []))
    related = ("sensor_id" in left_cols and "id" in right_cols) or ("id" in left_cols and "sensor_id" in right_cols)
    if related:
        sensor_frame = self if "sensor_id" in left_cols else right
        assert pd.api.types.is_integer_dtype(sensor_frame["sensor_id"].dtype), "sensor_id was not integer typed before joining"
        how = kwargs.get("how", args[0] if args else "inner")
        assert how == "inner", "The sensor/API join must be an inner join"
        _event("join")
    return _orig_df_merge(self, right, *args, **kwargs)
pd.DataFrame.merge = _df_merge

_orig_join = pd.DataFrame.join
def _join(self, other, *args, **kwargs):
    names = {getattr(self.index, "name", None), getattr(getattr(other, "index", None), "name", None)}
    if "sensor_id" in names and "id" in names:
        sensor_index = self.index if self.index.name == "sensor_id" else other.index
        assert pd.api.types.is_integer_dtype(sensor_index.dtype), "sensor_id was not integer typed before joining"
        how = kwargs.get("how", args[0] if args else "left")
        assert how == "inner", "The sensor/API join must be an inner join"
        _event("join")
    return _orig_join(self, other, *args, **kwargs)
pd.DataFrame.join = _join
'''
    with open(os.path.join(hook_dir, "sitecustomize.py"), "w") as f:
        f.write(textwrap.dedent(hook))
    os.chmod(os.path.join(hook_dir, "sitecustomize.py"), 0o644)

    if os.path.exists(event_path):
        os.remove(event_path)
    if os.path.exists(RESULT_PATH):
        os.remove(RESULT_PATH)

    server = ReusableHTTPServer(("127.0.0.1", 8080), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        env = os.environ.copy()
        env["PYTHONPATH"] = hook_dir + (os.pathsep + env["PYTHONPATH"] if env.get("PYTHONPATH") else "")
        env["ETL_VERIFY_EVENTS"] = event_path
        proc = subprocess.run(
            ["runuser", "-u", "user", "--", "env",
             f"PYTHONPATH={env['PYTHONPATH']}", f"ETL_VERIFY_EVENTS={event_path}",
             "python3", SCRIPT_PATH],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=5)

    assert proc.returncode == 0, f"ETL script failed when executed:\nSTDOUT:\n{proc.stdout}\nSTDERR:\n{proc.stderr}"
    assert requests_seen["data"] > 0, "The executed ETL script did not fetch http://127.0.0.1:8080/data"
    assert os.path.isfile(RESULT_PATH), "Executing run_etl.py did not create experiment_results.json"

    events = []
    if os.path.exists(event_path):
        with open(event_path) as f:
            events = [line.strip() for line in f if line.strip()]
    assert "drop" in events, "The pipeline did not drop/filter missing sensor_id values"
    assert "cast" in events, "The pipeline did not explicitly cast sensor_id to an integer dtype"
    assert "join" in events, "The pipeline did not perform the required inner join between the CSV and API data"
    first_join = events.index("join")
    assert events.index("drop") < first_join and events.index("cast") < first_join, (
        "Missing-ID handling and integer schema enforcement must happen before the join"
    )

    try:
        with open(RESULT_PATH) as f:
            results = json.load(f)
    except Exception as e:
        pytest.fail(f"Executed pipeline did not produce valid JSON: {e}")

    assert set(results.keys()) == {"sum_projected_f1", "average_posterior_mean"}, (
        "experiment_results.json must contain exactly the two requested keys"
    )
    actual_sum = results["sum_projected_f1"]
    actual_avg = results["average_posterior_mean"]
    assert isinstance(actual_sum, (int, float)) and not isinstance(actual_sum, bool)
    assert isinstance(actual_avg, (int, float)) and not isinstance(actual_avg, bool)
    assert math.isfinite(actual_sum) and math.isfinite(actual_avg)

    expected_sum = (reading_1_a * 0.5 + reading_2_a * 0.1) + (reading_1_b * 0.5 + reading_2_b * 0.1)
    expected_avg = (
        (2 + successes_a) / (4 + trials_a)
        + (2 + successes_b) / (4 + trials_b)
    ) / 2
    assert math.isclose(actual_sum, expected_sum, rel_tol=1e-9, abs_tol=1e-9), (
        f"Fresh-data sum_projected_f1 should be {expected_sum}, got {actual_sum}"
    )
    assert math.isclose(actual_avg, expected_avg, rel_tol=1e-9, abs_tol=1e-9), (
        f"Fresh-data average_posterior_mean should be {expected_avg}, got {actual_avg}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
