#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import signal
import socket
import stat
import subprocess
import sys
import time
import uuid

import pytest
import requests

PORT = 8443
API_KEY = "super-secret-token-99"
BASE_URL = f"http://127.0.0.1:{PORT}"
HEADERS = {"X-API-KEY": API_KEY}
SERVER_PATH = "/home/user/server.py"
REGRESSION_PATH = "/home/user/test_regression.py"


def wait_for_service(base_url=BASE_URL, timeout=8):
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        try:
            response = requests.get(f"{base_url}/logs", headers=HEADERS, timeout=0.5)
            if response.status_code == 200:
                return
        except requests.RequestException as exc:
            last_error = exc
        time.sleep(0.1)
    pytest.fail(f"Service did not become ready at {base_url}: {last_error}")


def listener_pids(port):
    inodes = set()
    wanted = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9 and fields[1].rsplit(":", 1)[-1].upper() == wanted and fields[3] == "0A":
                        inodes.add(fields[9])
        except OSError:
            pass

    pids = set()
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(name))
                    break
        except OSError:
            pass
    return pids


def stop_listener(port=PORT):
    pids = listener_pids(port)
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 4
    while time.time() < deadline and listener_pids(port):
        time.sleep(0.1)
    for pid in listener_pids(port):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    time.sleep(0.2)


def get_logs():
    response = requests.get(f"{BASE_URL}/logs", headers=HEADERS, timeout=3)
    assert response.status_code == 200, f"Expected HTTP 200 OK with valid API key, got {response.status_code}"
    data = response.json()
    assert "logs" in data, "Response JSON is missing the 'logs' key"
    assert isinstance(data["logs"], list), "The 'logs' value must be a list"
    return data["logs"]


def assert_batch_appended(payload):
    before = get_logs()
    response = requests.post(f"{BASE_URL}/logs", headers=HEADERS, json=payload, timeout=3)
    assert response.status_code == 200, f"Expected HTTP 200 OK on POST, got {response.status_code}"
    body = response.json()
    assert body.get("processed") == len(payload), (
        f"Expected processed count {len(payload)}, got {body.get('processed')}"
    )
    after = get_logs()
    assert after == before + payload, "The service did not store every submitted entry exactly once and in order"


def exercise_general_batches():
    marker = uuid.uuid4().hex
    for size in (1, 2, 4, 7):
        payload = [
            {"msg": f"{marker}-{size}-{i}", "index": i, "batch_size": size}
            for i in range(size)
        ]
        assert_batch_appended(payload)


def test_files_recovered_and_created():
    assert os.path.isfile(SERVER_PATH), "/home/user/server.py was not recovered or is missing"
    assert os.path.isfile(REGRESSION_PATH), "/home/user/test_regression.py was not created"


def test_service_authentication():
    try:
        response_no_auth = requests.get(f"{BASE_URL}/logs", timeout=3)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the service at {BASE_URL}. Is it running? Error: {e}")

    assert response_no_auth.status_code == 401, f"Expected HTTP 401 Unauthorized when no API key is provided, got {response_no_auth.status_code}"

    response_wrong_auth = requests.get(
        f"{BASE_URL}/logs", headers={"X-API-KEY": API_KEY + "-wrong"}, timeout=3
    )
    assert response_wrong_auth.status_code == 401, "An incorrect API key must be rejected"

    headers = {"X-API-KEY": API_KEY}
    response_auth = requests.get(f"{BASE_URL}/logs", headers=headers, timeout=3)
    assert response_auth.status_code == 200, f"Expected HTTP 200 OK with valid API key, got {response_auth.status_code}"

    before = response_auth.json().get("logs")
    assert isinstance(before, list)
    unauthorized = requests.post(f"{BASE_URL}/logs", json=[{"msg": uuid.uuid4().hex}], timeout=3)
    assert unauthorized.status_code == 401, "POST /logs must also require authentication"
    assert get_logs() == before, "An unauthorized POST changed stored logs"


def test_service_boundary_condition_fixed():
    headers = {"X-API-KEY": API_KEY}
    payload = [{"msg": "log1"}, {"msg": "log2"}, {"msg": "log3"}]
    before = get_logs()

    try:
        post_response = requests.post(f"{BASE_URL}/logs", headers=headers, json=payload, timeout=3)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to POST to the service at {BASE_URL}. Error: {e}")

    assert post_response.status_code == 200, f"Expected HTTP 200 OK on POST, got {post_response.status_code}"
    assert post_response.json().get("processed") == len(payload), "Processed count does not match the submitted batch"

    try:
        get_response = requests.get(f"{BASE_URL}/logs", headers=headers, timeout=3)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to GET from the service at {BASE_URL}. Error: {e}")

    assert get_response.status_code == 200, f"Expected HTTP 200 OK on GET, got {get_response.status_code}"

    data = get_response.json()
    assert "logs" in data, "Response JSON is missing the 'logs' key"
    logs = data["logs"]

    found_log3 = any(isinstance(log, dict) and log.get("msg") == "log3" for log in logs)
    assert found_log3, "The last log entry ('log3') was not found in the stored logs. The off-by-one boundary condition bug is not fixed."
    assert logs == before + payload, "The complete submitted batch was not stored exactly once and in order"

    exercise_general_batches()


def test_recovered_server_artifact_itself():
    stop_listener()
    env = os.environ.copy()
    env["PORT"] = str(PORT)
    env["API_KEY"] = API_KEY
    proc = subprocess.Popen(
        [sys.executable, SERVER_PATH],
        cwd="/home/user",
        env=env,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    try:
        wait_for_service()
        no_auth = requests.get(f"{BASE_URL}/logs", timeout=3)
        assert no_auth.status_code == 401
        exercise_general_batches()
    finally:
        try:
            os.killpg(proc.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        stop_listener()


def run_regression(timeout=20):
    proc = subprocess.Popen(
        [sys.executable, REGRESSION_PATH],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        start_new_session=True,
    )
    timed_out = False
    try:
        output, _ = proc.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        timed_out = True
        output = "regression script timed out"
    finally:
        try:
            os.killpg(proc.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
    return None if timed_out else proc.returncode, output


def test_regression_script_executes_and_detects_boundary_bug():
    with open(SERVER_PATH, "rb") as f:
        original = f.read()
    original_mode = stat.S_IMODE(os.stat(SERVER_PATH).st_mode)

    buggy_server = b'''from flask import Flask, request, jsonify\nimport os\napp = Flask(__name__)\nstored_logs = []\nAPI_KEY = os.environ.get("API_KEY", "super-secret-token-99")\n@app.before_request\ndef check_auth():\n    if request.headers.get("X-API-KEY") != API_KEY:\n        return jsonify({"error": "Unauthorized"}), 401\n@app.route("/logs", methods=["POST"])\ndef receive_logs():\n    data = request.json\n    if not data or not isinstance(data, list):\n        return jsonify({"error": "Invalid format"}), 400\n    for item in data[:-1]:\n        stored_logs.append(item)\n    return jsonify({"processed": max(0, len(data)-1)}), 200\n@app.route("/logs", methods=["GET"])\ndef get_logs():\n    return jsonify({"logs": stored_logs}), 200\nif __name__ == "__main__":\n    app.run(host="127.0.0.1", port=int(os.environ.get("PORT", 8443)))\n'''

    try:
        stop_listener()
        with open(SERVER_PATH, "wb") as f:
            f.write(buggy_server)
        os.chmod(SERVER_PATH, original_mode)
        bad_rc, bad_output = run_regression()
        assert bad_rc != 0, (
            "test_regression.py did not fail against a server that drops the last batch entry. "
            f"Output:\n{bad_output}"
        )
    finally:
        stop_listener()
        with open(SERVER_PATH, "wb") as f:
            f.write(original)
        os.chmod(SERVER_PATH, original_mode)

    stop_listener()
    good_rc, good_output = run_regression()
    stop_listener()
    assert good_rc == 0, f"test_regression.py failed against the repaired server. Output:\n{good_output}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
