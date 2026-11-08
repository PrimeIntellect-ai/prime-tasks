#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import random
import signal
import subprocess
import tempfile
import time
import urllib.request
import uuid

import pytest


def test_services_running():
    """Test that the Nginx proxy correctly routes to the Flask API."""
    url = "http://localhost:8080/api/vector"
    try:
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=2) as response:
            assert response.status == 200, f"Expected HTTP 200, got {response.status}"
            data = json.loads(response.read().decode("utf-8"))
            expected_data = {"v_x": 0.5, "v_y": -0.5, "v_z": 1.0}
            assert data == expected_data, f"Expected {expected_data}, got {data}"
    except Exception as e:
        pytest.fail(f"Failed to reach API through Nginx proxy at {url}: {e}")


def test_filter_script_exists_and_executable():
    """Test that the filter script exists and is executable."""
    script_path = "/home/user/filter.sh"
    assert os.path.isfile(script_path), f"Script {script_path} is missing."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."


def get_redis_set_members(set_name):
    """Helper to get members of a Redis set using redis-cli."""
    try:
        result = subprocess.run(
            ["redis-cli", "smembers", set_name],
            capture_output=True, text=True, check=True
        )
        return set(result.stdout.split())
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to query Redis set {set_name}: {e.stderr}")


def test_adversarial_corpus():
    """Test the script against the clean and evil corpora."""
    script_path = "/home/user/filter.sh"
    clean_dir = "/app/corpus/clean"
    evil_dir = "/app/corpus/evil"

    clean_files = glob.glob(os.path.join(clean_dir, "*.csv"))
    evil_files = glob.glob(os.path.join(evil_dir, "*.csv"))

    assert clean_files, "No clean files found in corpus."
    assert evil_files, "No evil files found in corpus."

    clean_failures = []
    evil_failures = []

    for f in clean_files:
        basename = os.path.basename(f)
        result = subprocess.run([script_path, f], capture_output=True)
        if result.returncode != 0:
            clean_failures.append(basename)

    for f in evil_files:
        basename = os.path.basename(f)
        result = subprocess.run([script_path, f], capture_output=True)
        if result.returncode != 1:
            evil_failures.append(basename)

    accepted_files = get_redis_set_members("accepted_files")
    rejected_files = get_redis_set_members("rejected_files")

    for f in clean_files:
        basename = os.path.basename(f)
        if basename not in accepted_files and basename not in clean_failures:
            clean_failures.append(f"{basename} (missing from Redis accepted_files)")

    for f in evil_files:
        basename = os.path.basename(f)
        if basename not in rejected_files and basename not in evil_failures:
            evil_failures.append(f"{basename} (missing from Redis rejected_files)")

    error_messages = []
    if evil_failures:
        error_messages.append(f"{len(evil_failures)} of {len(evil_files)} evil bypassed: {', '.join(evil_failures)}")
    if clean_failures:
        error_messages.append(f"{len(clean_failures)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_failures)}")

    if error_messages:
        pytest.fail(" | ".join(error_messages))


def _stop_original_api():
    """Stop the API process started from /app/services/api.py without shell matching."""
    for proc_path in glob.glob("/proc/[0-9]*/cmdline"):
        try:
            with open(proc_path, "rb") as fh:
                cmdline = fh.read().replace(b"\x00", b" ")
            if b"/app/services/api.py" in cmdline:
                pid = int(proc_path.split("/")[2])
                if pid != os.getpid():
                    os.kill(pid, signal.SIGTERM)
        except (FileNotFoundError, ProcessLookupError, PermissionError, ValueError):
            pass
    time.sleep(0.5)


def _wait_for_proxy_vector(expected):
    last_error = None
    for _ in range(50):
        try:
            with urllib.request.urlopen("http://localhost:8080/api/vector", timeout=1) as response:
                data = json.loads(response.read().decode("utf-8"))
                if data == expected:
                    return
        except Exception as exc:
            last_error = exc
        time.sleep(0.1)
    pytest.fail(f"Dynamic calibration API did not become available through Nginx: {last_error}")


def test_filter_on_unseen_inputs_and_runtime_calibration():
    """Exercise unseen paths and values using a calibration vector chosen at test time."""
    rng = random.SystemRandom()
    original = (0.5, -0.5, 1.0)

    while True:
        vector = tuple(round(rng.uniform(1.5, 4.5) * rng.choice((-1, 1)), 4) for _ in range(3))
        cross = (
            vector[1] * original[2] - vector[2] * original[1],
            vector[2] * original[0] - vector[0] * original[2],
            vector[0] * original[1] - vector[1] * original[0],
        )
        if sum(v * v for v in cross) > 2.0:
            break

    response_vector = {"v_x": vector[0], "v_y": vector[1], "v_z": vector[2]}
    server_code = r'''
import json
import os
from http.server import BaseHTTPRequestHandler, HTTPServer

VECTOR = json.loads(os.environ["TEST_VECTOR"])
class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != "/vector":
            self.send_response(404)
            self.end_headers()
            return
        body = json.dumps(VECTOR).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *args):
        pass

HTTPServer.allow_reuse_address = True
HTTPServer(("127.0.0.1", 5000), Handler).serve_forever()
'''

    _stop_original_api()
    env = os.environ.copy()
    env["TEST_VECTOR"] = json.dumps(response_vector)
    mock_api = subprocess.Popen(
        ["python3", "-c", server_code],
        env=env,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )

    try:
        _wait_for_proxy_vector(response_vector)

        def dot(row, calibration):
            return sum(row[i] * calibration[i] for i in range(3))

        clean_disagreement = None
        evil_disagreement = None
        for _ in range(200000):
            row = tuple(rng.uniform(-25.0, 25.0) for _ in range(3))
            new_value = abs(dot(row, vector))
            old_value = abs(dot(row, original))
            if clean_disagreement is None and new_value < 9.0 and old_value > 11.0:
                clean_disagreement = row
            if evil_disagreement is None and new_value > 11.0 and old_value < 9.0:
                evil_disagreement = row
            if clean_disagreement is not None and evil_disagreement is not None:
                break

        assert clean_disagreement is not None, "Could not construct a clean calibration-disagreement case"
        assert evil_disagreement is not None, "Could not construct an evil calibration-disagreement case"

        axis = max(range(3), key=lambda i: abs(vector[i]))
        near_clean = [0.0, 0.0, 0.0]
        near_clean[axis] = 9.999 / vector[axis]
        near_evil = [0.0, 0.0, 0.0]
        near_evil[axis] = -10.001 / vector[axis]

        cases = [
            ([clean_disagreement, (0.0, 0.0, 0.0)], False),
            ([(0.0, 0.0, 0.0), evil_disagreement], True),
            ([(tuple(near_clean))], False),
            ([(0.0, 0.0, 0.0), tuple(near_evil)], True),
        ]

        with tempfile.TemporaryDirectory(prefix="sensor-validation-") as temp_dir:
            generated = []
            for rows, expected_anomalous in cases:
                name = f"sample-{uuid.uuid4().hex}.csv"
                path = os.path.join(temp_dir, name)
                with open(path, "w", encoding="utf-8") as fh:
                    for sensor_id, row in enumerate(rows, start=1000):
                        fh.write(f"{sensor_id},{row[0]:.12f},{row[1]:.12f},{row[2]:.12f}\n")

                parsed_rows = [tuple(float(f"{value:.12f}") for value in row) for row in rows]
                derived_anomalous = any(abs(dot(row, vector)) > 10.000 for row in parsed_rows)
                assert derived_anomalous == expected_anomalous
                generated.append((path, name, derived_anomalous))

            names = [name for _, name, _ in generated]
            subprocess.run(["redis-cli", "srem", "accepted_files", *names], check=True, capture_output=True)
            subprocess.run(["redis-cli", "srem", "rejected_files", *names], check=True, capture_output=True)

            for path, name, anomalous in generated:
                result = subprocess.run(
                    ["/home/user/filter.sh", os.path.abspath(path)],
                    capture_output=True,
                    text=True,
                    timeout=10,
                )
                expected_exit = 1 if anomalous else 0
                assert result.returncode == expected_exit, (
                    f"{name}: expected exit {expected_exit}, got {result.returncode}; "
                    f"stdout={result.stdout!r}, stderr={result.stderr!r}"
                )

            accepted = get_redis_set_members("accepted_files")
            rejected = get_redis_set_members("rejected_files")
            for _, name, anomalous in generated:
                if anomalous:
                    assert name in rejected, f"{name} missing from rejected_files"
                    assert name not in accepted, f"{name} incorrectly added to accepted_files"
                else:
                    assert name in accepted, f"{name} missing from accepted_files"
                    assert name not in rejected, f"{name} incorrectly added to rejected_files"
    finally:
        mock_api.terminate()
        try:
            mock_api.wait(timeout=2)
        except subprocess.TimeoutExpired:
            mock_api.kill()
            mock_api.wait(timeout=2)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
