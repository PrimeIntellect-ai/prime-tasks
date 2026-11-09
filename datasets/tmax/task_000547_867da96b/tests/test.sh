#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import json
import math
import os
import signal
import stat
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import pytest
import requests


def test_start_services_script_exists_and_executable():
    script_path = "/home/user/start_services.sh"
    assert os.path.isfile(script_path), f"{script_path} does not exist."
    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"{script_path} is not executable."


def test_regression_test_script_exists():
    script_path = "/home/user/regression_test.py"
    assert os.path.isfile(script_path), f"{script_path} does not exist."


def test_coordinator_run_sim_100_2():
    url = "http://127.0.0.1:5000/run_sim"
    payload = {"N": 100, "workers": 2}
    try:
        response = requests.post(url, json=payload, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to coordinator at {url}: {e}")

    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"

    data = response.json()
    assert isinstance(data, list), "Expected a JSON array response"
    assert len(data) == 100, f"Expected length 100, got {len(data)}"

    expected = [math.sin(i * 0.1) for i in range(100)]
    for i, (val, exp) in enumerate(zip(data, expected)):
        assert abs(val - exp) < 1e-5, f"Mismatch at index {i}: expected {exp}, got {val}"


def test_regression_test_execution():
    script_path = "/home/user/regression_test.py"
    result = subprocess.run(["python3", script_path], capture_output=True, text=True, timeout=15)
    assert result.returncode == 0, f"regression_test.py failed with return code {result.returncode}\nstderr: {result.stderr}"
    assert "REGRESSION_PASSED" in result.stdout, f"Expected 'REGRESSION_PASSED' in stdout, got: {result.stdout}"


def test_split_mesh_105_4_remainder_distribution():
    path = "/app/sim_env/coordinator.py"
    assert os.path.isfile(path), f"{path} does not exist"
    spec = importlib.util.spec_from_file_location("submitted_coordinator", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert module.split_mesh(105, 4) == [
        (0, 27),
        (27, 53),
        (53, 79),
        (79, 105),
    ]


def _listener_pids(ports):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local_port = int(fields[1].split(":")[1], 16)
                    state = fields[3]
                    if local_port in ports and state == "0A":
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

    pids = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit() or int(entry) == os.getpid():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(entry))
                    break
        except (FileNotFoundError, PermissionError):
            continue
    return pids


def _stop_service_listeners():
    ports = {5000, 5001, 5002, 8080}
    pids = _listener_pids(ports)
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
    while time.time() < deadline and _listener_pids(ports):
        time.sleep(0.05)
    for pid in _listener_pids(ports):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while time.time() < deadline and _listener_pids(ports):
        time.sleep(0.05)
    assert not _listener_pids(ports), "Could not free service ports for regression-script verification"


def test_regression_script_really_requests_and_compares():
    expected = [math.sin(i * 0.1) for i in range(100)]
    state = {"reference": list(expected), "posts": [], "gets": []}

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass

        def _send_json(self, value):
            body = json.dumps(value).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_POST(self):
            length = int(self.headers.get("Content-Length", "0"))
            body = self.rfile.read(length)
            payload = json.loads(body.decode())
            state["posts"].append((self.path, payload))
            if self.server.server_port == 5000 and self.path == "/run_sim":
                self._send_json(expected)
            else:
                self.send_error(404)

        def do_GET(self):
            state["gets"].append(self.path)
            if self.server.server_port == 8080 and self.path == "/reference.json":
                self._send_json(state["reference"])
            else:
                self.send_error(404)

    _stop_service_listeners()
    coordinator = ThreadingHTTPServer(("127.0.0.1", 5000), Handler)
    data_server = ThreadingHTTPServer(("127.0.0.1", 8080), Handler)
    threads = [
        threading.Thread(target=coordinator.serve_forever, daemon=True),
        threading.Thread(target=data_server.serve_forever, daemon=True),
    ]
    for thread in threads:
        thread.start()

    try:
        passed = subprocess.run(
            ["python3", "/home/user/regression_test.py"],
            capture_output=True,
            text=True,
            timeout=15,
        )
        assert passed.returncode == 0, passed.stderr
        assert "REGRESSION_PASSED" in passed.stdout
        assert ("/run_sim", {"N": 100, "workers": 2}) in state["posts"], \
            f"Regression script did not send the required coordinator request: {state['posts']}"
        assert "/reference.json" in state["gets"], \
            f"Regression script did not fetch the reference dataset: {state['gets']}"

        state["reference"] = list(expected)
        state["reference"][37] += 1e-3
        failed = subprocess.run(
            ["python3", "/home/user/regression_test.py"],
            capture_output=True,
            text=True,
            timeout=15,
        )
        assert failed.returncode == 0, failed.stderr
        assert "REGRESSION_FAILED" in failed.stdout, \
            f"Regression script did not detect a mismatching reference: {failed.stdout}"
        assert "REGRESSION_PASSED" not in failed.stdout, \
            f"Regression script reported success for mismatching data: {failed.stdout}"
    finally:
        coordinator.shutdown()
        data_server.shutdown()
        coordinator.server_close()
        data_server.server_close()
        for thread in threads:
            thread.join(timeout=2)
        try:
            subprocess.run(
                ["/home/user/start_services.sh"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=15,
                check=False,
            )
        except subprocess.TimeoutExpired:
            pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
