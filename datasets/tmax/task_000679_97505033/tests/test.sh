#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import json
import os
import re
import signal
import socket
import subprocess
import sys
import tempfile
import time
import uuid

import pytest
import redis
import requests


def test_minimal_payload_correct():
    """Verify that the minimal payload was correctly identified and saved."""
    payload_path = "/home/user/minimal_payload.json"
    assert os.path.exists(payload_path), f"Minimal payload file {payload_path} does not exist."
    assert os.path.isfile(payload_path), f"{payload_path} is not a file."

    with open(payload_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{payload_path} is not a valid JSON file.")

    expected_payload = {"filters": {"metadata": {"is_archived": True}}}
    assert data == expected_payload, f"Minimal payload does not match the expected minimal JSON. Got: {data}"


def test_bad_commit_correct():
    """Verify that the student found the correct bad commit hash."""
    commit_file = "/home/user/bad_commit.txt"
    assert os.path.exists(commit_file), f"Bad commit file {commit_file} does not exist."

    with open(commit_file, 'r') as f:
        student_commit = f.read().strip()

    repo_path = "/app/api_repo"
    try:
        result = subprocess.run(
            ["git", "log", "--grep=Feature: filter by archive status", "--format=%H"],
            cwd=repo_path,
            capture_output=True,
            text=True,
            check=True
        )
        expected_commit = result.stdout.strip()
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to run git log in {repo_path}: {e.stderr}")

    assert expected_commit != "", "Could not find the expected commit in the repository."
    assert student_commit == expected_commit, f"Incorrect bad commit. Expected {expected_commit}, got {student_commit}"
    assert re.fullmatch(r"[0-9a-f]{40}", student_commit), "bad_commit.txt must contain one full commit hash."

    subprocess.run(
        ["git", "cat-file", "-e", student_commit + "^{commit}"],
        cwd=repo_path, check=True, capture_output=True, text=True
    )

    # Confirm behaviorally that this commit, rather than merely its message,
    # introduced the archived-filter crash: its first parent must work and the
    # named commit must return HTTP 500 for the minimized reproducer.
    def status_at(revision):
        source = subprocess.run(
            ["git", "show", revision + ":app.py"],
            cwd=repo_path, capture_output=True, text=True, check=True
        ).stdout
        with tempfile.TemporaryDirectory() as td:
            app_path = os.path.join(td, "app.py")
            with open(app_path, "w") as f:
                f.write(source)
            runner = os.path.join(td, "run.py")
            with open(runner, "w") as f:
                f.write(
                    "import importlib.util\n"
                    "spec=importlib.util.spec_from_file_location('candidate', 'app.py')\n"
                    "m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m)\n"
                    "m.app.testing=False\n"
                    "r=m.app.test_client().post('/query', json={'filters': {'metadata': {'is_archived': True}}})\n"
                    "print('STATUS=' + str(r.status_code))\n"
                )
            result = subprocess.run(
                [sys.executable, runner], cwd=td, capture_output=True, text=True, timeout=10
            )
            match = re.search(r"STATUS=(\d+)", result.stdout)
            assert match, f"Could not exercise app.py at {revision}: {result.stderr}"
            return int(match.group(1))

    parent_line = subprocess.run(
        ["git", "rev-list", "--parents", "-n", "1", student_commit],
        cwd=repo_path, capture_output=True, text=True, check=True
    ).stdout.split()
    assert len(parent_line) >= 2, "The reported bad commit has no parent to compare against."
    assert status_at(parent_line[1]) == 200, "The parent of the reported commit was not known-good."
    assert status_at(student_commit) == 500, "The reported commit does not introduce the reproduced HTTP 500."


def test_upstream_services_running():
    """Both required upstream ports must host the expected protocols."""
    try:
        assert redis.Redis(host="127.0.0.1", port=6379, socket_timeout=2).ping() is True
    except Exception as e:
        pytest.fail(f"Redis is not running on 127.0.0.1:6379: {e}")

    try:
        response = requests.get("http://127.0.0.1:9000/", timeout=3)
        response.raise_for_status()
        body = response.json()
    except Exception as e:
        pytest.fail(f"Data Service is not running on 127.0.0.1:9000: {e}")
    assert isinstance(body, dict) and isinstance(body.get("data"), list), \
        f"Unexpected Data Service response: {body}"


def test_api_fixed_and_running():
    """Verify that the API is running, the bug is fixed, and it returns a 200 OK."""
    url = "http://127.0.0.1:8000/query"
    payload = {"filters": {"metadata": {"is_archived": True}}}

    try:
        response = requests.post(url, json=payload, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the Flask API at {url}. Is it running? Error: {e}")

    assert response.status_code == 200, f"Expected HTTP 200 OK, got {response.status_code}. Response body: {response.text}"

    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"API did not return valid JSON. Response body: {response.text}")

    assert data.get("status") == "success", f"Expected 'status': 'success' in response, got: {data}"


def _listener_pids(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if int(fields[1].split(":")[1], 16) == port and fields[3] == "0A":
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass
    pids = set()
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(name))
        except (FileNotFoundError, PermissionError):
            pass
    return pids


def _wait_port(port, should_be_open, timeout=5):
    deadline = time.time() + timeout
    while time.time() < deadline:
        with socket.socket() as s:
            s.settimeout(0.2)
            open_now = s.connect_ex(("127.0.0.1", port)) == 0
        if open_now == should_be_open:
            return
        time.sleep(0.05)
    raise AssertionError(f"Port {port} did not become {'open' if should_be_open else 'closed'}")


def test_api_and_patched_app_use_data_service_for_varied_payloads():
    """Reject a constant-success replacement and exercise the submitted app.py."""
    app_path = "/app/api_repo/app.py"
    assert os.path.isfile(app_path), "The required /app/api_repo/app.py is missing."

    # Replace the mock Data Service temporarily with a verifier-controlled one
    # whose unpredictable results must be propagated by both the live API and
    # the submitted Flask application object.
    for pid in _listener_pids(9000):
        os.kill(pid, signal.SIGTERM)
    _wait_port(9000, False)

    secret = uuid.uuid4().hex
    log_path = "/tmp/verifier_data_service.jsonl"
    server_path = "/tmp/verifier_data_service.py"
    try:
        os.unlink(log_path)
    except FileNotFoundError:
        pass
    with open(server_path, "w") as f:
        f.write(r'''from http.server import BaseHTTPRequestHandler, HTTPServer
import json, sys
secret, log_path = sys.argv[1], sys.argv[2]
count = 0
class H(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass
    def do_POST(self):
        global count
        count += 1
        length = int(self.headers.get('Content-Length', '0'))
        if length:
            self.rfile.read(length)
        data = [{"token": secret + "-" + str(count), "upstream": True}]
        with open(log_path, 'a') as out:
            out.write(json.dumps({"data": data}) + "\n")
            out.flush()
        body = json.dumps({"data": data}).encode()
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def do_GET(self):
        self.do_POST()
HTTPServer(('127.0.0.1', 9000), H).serve_forever()
''')

    controlled = subprocess.Popen(
        [sys.executable, server_path, secret, log_path],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )
    try:
        _wait_port(9000, True)

        module_name = "submitted_app_" + uuid.uuid4().hex
        spec = importlib.util.spec_from_file_location(module_name, app_path)
        assert spec is not None and spec.loader is not None, "app.py is not importable Python."
        submitted = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(submitted)
        assert hasattr(submitted, "app") and hasattr(submitted.app, "test_client"), \
            "app.py does not define the required Flask application."
        submitted.app.testing = False
        client = submitted.app.test_client()

        payloads = [
            {"filters": {"metadata": {"is_archived": True}}},
            {},
            {"filters": {"metadata": {"is_archived": False}}},
            {"query_id": "different", "limit": 7},
            {"filters": {"metadata": {"is_archived": True, "tags": ["x"]}}},
        ]

        def records():
            try:
                with open(log_path) as f:
                    return [json.loads(line) for line in f if line.strip()]
            except FileNotFoundError:
                return []

        def assert_propagated(response, before, label):
            assert response.status_code == 200, f"{label} returned {response.status_code}: {response.get_data(as_text=True) if hasattr(response, 'get_data') else response.text}"
            body = response.get_json() if hasattr(response, "get_json") else response.json()
            assert body.get("status") == "success", f"{label} returned unexpected JSON: {body}"
            deadline = time.time() + 2
            seen = records()
            while len(seen) <= before and time.time() < deadline:
                time.sleep(0.02)
                seen = records()
            assert len(seen) > before, f"{label} did not contact the Data Service on port 9000."
            assert body.get("results") == seen[-1]["data"], \
                f"{label} did not propagate the Data Service's derived result: {body}"

        for payload in payloads:
            before = len(records())
            live = requests.post("http://127.0.0.1:8000/query", json=payload, timeout=5)
            assert_propagated(live, before, "Live API")

            before = len(records())
            direct = client.post("/query", json=payload)
            assert_propagated(direct, before, "Submitted app.py")
    finally:
        controlled.terminate()
        try:
            controlled.wait(timeout=3)
        except subprocess.TimeoutExpired:
            controlled.kill()
            controlled.wait()
        _wait_port(9000, False)
        subprocess.Popen(
            [sys.executable, "/app/services/data_service/server.py"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )
        _wait_port(9000, True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
