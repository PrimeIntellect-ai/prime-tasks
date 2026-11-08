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
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import signal
import subprocess
import time
import uuid

import requests

APP_DIR = "/home/user/app"
URL = "http://127.0.0.1:8080/telemetry"
LOG_PATH = os.path.join(APP_DIR, "processed_telemetry.log")


def redis_cli(*args):
    result = subprocess.run(
        ["redis-cli", "-h", "127.0.0.1", "-p", "6379", "--raw", *args],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=3,
    )
    assert result.returncode == 0, f"redis-cli {' '.join(args)} failed: {result.stderr}"
    return result.stdout.rstrip("\n")


def script_processes(script_name):
    found = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit() or int(entry) == os.getpid():
            continue
        proc_dir = os.path.join("/proc", entry)
        try:
            with open(os.path.join(proc_dir, "cmdline"), "rb") as f:
                args = [part.decode(errors="replace") for part in f.read().split(b"\0") if part]
            cwd = os.readlink(os.path.join(proc_dir, "cwd"))
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue

        absolute_script = os.path.join(APP_DIR, script_name)
        if absolute_script in args or (script_name in args and cwd == APP_DIR):
            found.append(int(entry))
    return found


def signal_processes(pids, sig):
    for pid in pids:
        try:
            os.kill(pid, sig)
        except ProcessLookupError:
            pass


def log_contains(line):
    if not os.path.exists(LOG_PATH):
        return False
    with open(LOG_PATH, "r") as f:
        return line in f.read()


def test_required_artifacts_and_services_exist():
    for path in (os.path.join(APP_DIR, "ingest.py"), os.path.join(APP_DIR, "worker.py")):
        assert os.path.isfile(path), f"Required script {path} does not exist or is not a regular file"
        assert not os.path.islink(path), f"Required script {path} must not be a symlink"

    venv_python = os.path.join(APP_DIR, "venv", "bin", "python")
    assert os.path.isfile(os.path.join(APP_DIR, "venv", "pyvenv.cfg")), "Missing virtual environment at /home/user/app/venv"
    assert os.path.exists(venv_python), "Virtual environment Python interpreter is missing"
    result = subprocess.run(
        [venv_python, "-c", "import flask, redis"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=5,
    )
    assert result.returncode == 0, f"flask and redis must be installed in the virtual environment: {result.stderr}"

    assert redis_cli("PING") == "PONG", "Redis is not available on 127.0.0.1:6379"
    assert script_processes("ingest.py"), "No running ingest.py service process was found"
    assert script_processes("worker.py"), "No running worker.py service process was found"


def test_unauthorized_request():
    """Verify that the API rejects unauthorized requests."""
    headers = {
        "Authorization": "Bearer invalid-token",
        "Content-Type": "application/json"
    }
    payload = {"device_id": "test-device", "metric": 10.0}

    try:
        response = requests.post(URL, json=payload, headers=headers, timeout=2)
    except requests.exceptions.RequestException as e:
        raise AssertionError(f"Failed to connect to the ingest-api on 127.0.0.1:8080: {e}")

    assert response.status_code == 401, f"Expected 401 Unauthorized, got {response.status_code}. Response: {response.text}"


def test_api_redis_worker_architecture():
    """Prove the API queues the exact body and the separate worker consumes it."""
    worker_pids = script_processes("worker.py")
    ingest_pids = script_processes("ingest.py")
    assert worker_pids, "No running worker.py process was found"
    assert ingest_pids, "No running ingest.py process was found"

    unique_id = f"broker-{uuid.uuid4().hex}"
    exact_payload = json.dumps({"device_id": unique_id, "metric": 17.25}, separators=(",", ":"))
    expected_line = f"DEVICE:{unique_id},METRIC:17.25"
    headers = {
        "Authorization": "Bearer rel-mgr-token-992",
        "Content-Type": "application/json",
    }

    signal_processes(worker_pids, signal.SIGSTOP)
    ingest_stopped = False
    try:
        redis_cli("DEL", "telemetry_queue")
        assert not log_contains(expected_line), "Unique architecture-test line unexpectedly existed before the request"

        response = requests.post(URL, data=exact_payload, headers=headers, timeout=2)
        assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}. Response: {response.text}"
        try:
            response_data = response.json()
        except ValueError:
            raise AssertionError(f"Response was not valid JSON: {response.text}")
        assert response_data.get("status") == "queued", f"Expected response JSON {{'status': 'queued'}}, got {response_data}"

        # A stopped worker cannot have written this. This rejects an API that directly writes the log.
        assert not log_contains(expected_line), "The telemetry line was written while every worker.py process was stopped"
        assert redis_cli("TYPE", "telemetry_queue") == "list", "telemetry_queue is not a Redis list"
        assert redis_cli("LLEN", "telemetry_queue") == "1", "The authorized request was not added once to telemetry_queue"
        queued = redis_cli("LINDEX", "telemetry_queue", "0")
        assert queued == exact_payload, f"Redis did not contain the exact request JSON. Expected {exact_payload!r}, got {queued!r}"

        # Freeze the API before allowing the worker to run, proving that the worker performs the log write.
        signal_processes(ingest_pids, signal.SIGSTOP)
        ingest_stopped = True
        signal_processes(worker_pids, signal.SIGCONT)

        found = False
        for _ in range(30):
            if log_contains(expected_line):
                found = True
                break
            time.sleep(0.2)
        assert found, f"worker.py did not consume telemetry_queue and append {expected_line!r} to {LOG_PATH}"
        assert redis_cli("LLEN", "telemetry_queue") == "0", "worker.py did not remove the item from telemetry_queue"
    finally:
        signal_processes(worker_pids, signal.SIGCONT)
        if ingest_stopped:
            signal_processes(ingest_pids, signal.SIGCONT)
        time.sleep(0.2)


def test_end_to_end_telemetry_pipeline():
    """Verify the full pipeline: API -> Redis -> Worker -> Log file."""
    headers = {
        "Authorization": "Bearer rel-mgr-token-992",
        "Content-Type": "application/json"
    }

    unique_id = f"sensor-{uuid.uuid4().hex[:8]}"
    metric_val = 42.5
    payload = {"device_id": unique_id, "metric": metric_val}

    try:
        response = requests.post(URL, json=payload, headers=headers, timeout=2)
    except requests.exceptions.RequestException as e:
        raise AssertionError(f"Failed to connect to the ingest-api on 127.0.0.1:8080: {e}")

    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}. Response: {response.text}"

    try:
        data = response.json()
        assert data.get("status") == "queued", f"Expected response JSON {{'status': 'queued'}}, got {data}"
    except ValueError:
        raise AssertionError(f"Response was not valid JSON: {response.text}")

    expected_log_line = f"DEVICE:{unique_id},METRIC:{metric_val}"
    found = False
    for _ in range(20):
        if log_contains(expected_log_line):
            found = True
            break
        time.sleep(0.2)

    if not found:
        if not os.path.exists(LOG_PATH):
            raise AssertionError(f"Log file {LOG_PATH} was not created by the worker.")
        with open(LOG_PATH, "r") as f:
            content = f.read()
        raise AssertionError(f"Expected to find '{expected_log_line}' in {LOG_PATH}, but it was not there. Current content:\n{content}")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
