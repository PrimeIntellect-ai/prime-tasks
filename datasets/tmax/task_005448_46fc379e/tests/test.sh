#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
mkdir -p /logs/verifier

# Ensure verification exercises the submitted server.py rather than an unrelated
# process the agent may have left listening on the port.
pkill -f 'python[^ ]* .*server.py' 2>/dev/null || true
sleep 1

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import json
import math
import os
import re
import sqlite3
import statistics
import subprocess
import sys
import threading
import time

import cv2
import numpy as np
import pytest
import requests

SERVER = "/home/user/service_repo/server.py"
REPO = "/home/user/service_repo"
DB = "/home/user/incident_data/metrics.db"
VIDEO = "/app/incident.mp4"


def recover_expected_id():
    assert os.path.isfile(DB), "metrics.db is missing"
    conn = sqlite3.connect(f"file:{DB}?mode=ro", uri=True)
    try:
        integrity = conn.execute("PRAGMA integrity_check").fetchone()[0]
        assert integrity == "ok", f"Recovered database failed integrity check: {integrity}"
        value = conn.execute("SELECT MAX(processed_id) FROM jobs").fetchone()[0]
    finally:
        conn.close()
    assert isinstance(value, int)
    return value


def recover_expected_red_frame():
    assert os.path.isfile(VIDEO), "incident video is missing"
    cap = cv2.VideoCapture(VIDEO)
    assert cap.isOpened(), "Could not open incident video"
    matches = []
    index = 0
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        # MP4 is lossy, so identify the encoded representation of an otherwise
        # uniform pure-red frame with a small codec tolerance.
        b, g, r = cv2.split(frame)
        if np.all(r >= 245) and np.all(g <= 10) and np.all(b <= 10):
            matches.append(index)
        index += 1
    cap.release()
    assert index > 0, "Video contained no decodable frames"
    assert len(matches) == 1, f"Expected one red frame, found {matches}"
    return matches[0]


def recover_expected_secret():
    assert os.path.isdir(os.path.join(REPO, ".git")), "Service repository is missing"
    result = subprocess.run(
        ["git", "fsck", "--full", "--no-reflogs", "--unreachable"],
        cwd=REPO, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        check=True,
    )
    secrets = set()
    for line in result.stdout.splitlines():
        match = re.match(r"unreachable commit ([0-9a-fA-F]+)$", line.strip())
        if not match:
            continue
        shown = subprocess.run(
            ["git", "show", f"{match.group(1)}:config.py"], cwd=REPO,
            text=True, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
        )
        if shown.returncode == 0:
            secrets.update(re.findall(r"SECRET_TOKEN\s*=\s*['\"]([^'\"]+)['\"]", shown.stdout))
    assert len(secrets) == 1, f"Expected exactly one secret in unreachable history, found {secrets}"
    return next(iter(secrets))


@pytest.fixture(scope="session")
def expected():
    values = {
        "secret_token": recover_expected_secret(),
        "red_frame": recover_expected_red_frame(),
        "recovered_id": recover_expected_id(),
    }
    # Preserve the original task's known-answer assertions as well as deriving
    # the answers independently from the incident artifacts.
    assert values["secret_token"] == "dev_token_9x2b_lost"
    assert values["red_frame"] == 87
    assert values["recovered_id"] == 14092
    return values


@pytest.fixture(scope="session")
def server_process():
    assert os.path.isfile(SERVER), "server.py is missing"
    assert not os.path.islink(SERVER), "server.py must be a submitted regular file"
    subprocess.run([sys.executable, "-m", "py_compile", SERVER], check=True)
    log = open("/tmp/submitted_server.log", "w+")
    proc = subprocess.Popen([sys.executable, SERVER], cwd=REPO, stdout=log, stderr=subprocess.STDOUT)
    url = "http://127.0.0.1:8000/api/report"
    for _ in range(50):
        if proc.poll() is not None:
            log.seek(0)
            pytest.fail(f"Submitted server.py exited during startup:\n{log.read()}")
        try:
            requests.get(url, timeout=0.5)
            break
        except requests.RequestException:
            time.sleep(0.1)
    else:
        proc.terminate()
        pytest.fail("Submitted server.py did not listen on 127.0.0.1:8000")
    yield proc
    proc.terminate()
    try:
        proc.wait(timeout=3)
    except subprocess.TimeoutExpired:
        proc.kill()
    log.close()


def test_api_report_endpoint(server_process, expected):
    response = requests.get("http://127.0.0.1:8000/api/report", timeout=2)
    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail("Response is not valid JSON")

    assert "secret_token" in data, "Missing 'secret_token' in JSON response"
    assert data["secret_token"] == "dev_token_9x2b_lost", f"Incorrect secret_token: {data['secret_token']}"
    assert "red_frame" in data, "Missing 'red_frame' in JSON response"
    assert data["red_frame"] == 87, f"Incorrect red_frame: {data['red_frame']}"
    assert "recovered_id" in data, "Missing 'recovered_id' in JSON response"
    assert data["recovered_id"] == 14092, f"Incorrect recovered_id: {data['recovered_id']}"

    assert data["secret_token"] == expected["secret_token"]
    assert data["red_frame"] == expected["red_frame"]
    assert data["recovered_id"] == expected["recovered_id"]
    assert isinstance(data["secret_token"], str)
    assert isinstance(data["red_frame"], int) and not isinstance(data["red_frame"], bool)
    assert isinstance(data["recovered_id"], int) and not isinstance(data["recovered_id"], bool)


def load_submitted_module():
    spec = importlib.util.spec_from_file_location("submitted_incident_server", SERVER)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_metrics_calculation_is_serialized():
    module = load_submitted_module()
    assert hasattr(module, "app"), "server.py does not define the Flask app"
    assert hasattr(module, "Metrics"), "server.py no longer defines the metrics implementation"

    module.metrics = module.Metrics()
    values = [(-1000.0 + i * 17.25) for i in range(64)]
    barrier = threading.Barrier(len(values))
    errors = []

    # Force thread switches between source lines in update(). Without
    # synchronization, Welford's dependent updates interleave and produce the
    # wrong mean/variance. A lock in either the route or update() serializes them.
    def tracer(frame, event, arg):
        if event == "line" and os.path.abspath(frame.f_code.co_filename) == SERVER and frame.f_code.co_name == "update":
            time.sleep(0.0005)
        return tracer

    old_trace = threading.gettrace() if hasattr(threading, "gettrace") else None
    threading.settrace(tracer)

    def post_value(value):
        try:
            barrier.wait(timeout=5)
            with module.app.test_client() as client:
                response = client.post("/api/metrics", json={"value": value})
                if response.status_code != 200:
                    errors.append(f"POST /api/metrics returned {response.status_code}")
        except Exception as exc:
            errors.append(repr(exc))

    threads = [threading.Thread(target=post_value, args=(v,)) for v in values]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join(timeout=10)
    threading.settrace(old_trace)

    assert all(not thread.is_alive() for thread in threads), "Concurrent metric updates deadlocked"
    assert not errors, f"Concurrent metric requests failed: {errors[0]}"
    assert module.metrics.count == len(values), "Concurrent updates lost metric samples"
    assert math.isclose(module.metrics.mean, statistics.fmean(values), rel_tol=1e-10, abs_tol=1e-10), \
        f"Concurrent mean is incorrect: {module.metrics.mean}"
    assert math.isclose(module.metrics.get_variance(), statistics.variance(values), rel_tol=1e-10, abs_tol=1e-8), \
        f"Concurrent variance is incorrect: {module.metrics.get_variance()}"


def test_live_metrics_endpoint_uses_post_and_survives_concurrency(server_process):
    url = "http://127.0.0.1:8000/api/metrics"
    errors = []

    def hammer(offset):
        for i in range(20):
            try:
                response = requests.post(url, json={"value": offset + i / 10.0}, timeout=3)
                if response.status_code != 200:
                    errors.append(f"status {response.status_code}")
            except Exception as exc:
                errors.append(repr(exc))

    threads = [threading.Thread(target=hammer, args=(i * 100,)) for i in range(10)]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join(timeout=15)
    assert all(not thread.is_alive() for thread in threads), "Live concurrent requests timed out"
    assert not errors, f"Concurrency test failed: {errors[0]}"
    assert server_process.poll() is None, "Service crashed under concurrent POST requests"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
