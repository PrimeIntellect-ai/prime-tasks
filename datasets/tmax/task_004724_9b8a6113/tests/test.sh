#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import signal
import subprocess
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import pytest
import requests

VENV_PYTHON = "/home/user/venv/bin/python"


def kill_service(script_path):
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            with open(f"/proc/{entry}/cmdline", "rb") as f:
                cmdline = f.read().replace(b"\0", b" ").decode(errors="ignore")
            if script_path in cmdline:
                os.kill(int(entry), signal.SIGTERM)
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            pass
    time.sleep(0.5)


def service_pids(script_path):
    result = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            with open(f"/proc/{entry}/cmdline", "rb") as f:
                cmdline = f.read().replace(b"\0", b" ").decode(errors="ignore")
            if script_path in cmdline:
                result.append(int(entry))
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            pass
    return result


def wait_for_url(url, timeout=10):
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        try:
            response = requests.get(url, timeout=1)
            if response.status_code == 200:
                return response
        except requests.RequestException as exc:
            last_error = exc
        time.sleep(0.15)
    pytest.fail(f"Service at {url} did not become ready: {last_error}")


def expected_for_file(path):
    compute_script = r'''
import h5py
import numpy as np
import json
import sys

with h5py.File(sys.argv[1], 'r') as f:
    M = f['spectroscopy/raw'][:]
    b = f['spectroscopy/vector'][:]

U, S, Vt = np.linalg.svd(M, full_matrices=False)
S_filtered = np.zeros_like(S)
S_filtered[:3] = S[:3]
M_filtered = U @ np.diag(S_filtered) @ Vt
x, _, _, _ = np.linalg.lstsq(M_filtered, b, rcond=None)
print(json.dumps(x.tolist()))
'''
    try:
        result = subprocess.run(
            [VENV_PYTHON, "-c", compute_script, path],
            capture_output=True, text=True, check=True
        )
        return json.loads(result.stdout.strip())
    except subprocess.CalledProcessError as exc:
        pytest.fail(f"Failed to compute expected result using student's venv: {exc.stderr}")
    except json.JSONDecodeError:
        pytest.fail(f"Failed to parse expected result. Output: {result.stdout}")


def assert_vector(actual, expected):
    assert isinstance(actual, list), f"Expected a JSON list of floats, got {type(actual).__name__}."
    assert len(actual) == len(expected), f"Expected list of length {len(expected)}, got {len(actual)}."
    for i, (act, exp) in enumerate(zip(actual, expected)):
        assert isinstance(act, (int, float)), f"Element at index {i} is not a number: {act}"
        assert math.isclose(act, exp, rel_tol=1e-4, abs_tol=1e-5), \
            f"Mismatch at index {i}: expected {exp}, got {act}"


def test_venv_exists_and_packages_installed():
    venv_dir = "/home/user/venv"
    assert os.path.isdir(venv_dir), f"Virtual environment directory {venv_dir} does not exist."
    assert os.path.isfile(VENV_PYTHON), f"Python executable not found at {VENV_PYTHON}."

    import_check = "import numpy, h5py, flask, requests, scipy"
    result = subprocess.run([VENV_PYTHON, "-c", import_check], capture_output=True, text=True)
    assert result.returncode == 0, f"Required packages are not importable in the venv: {result.stderr}"

    result = subprocess.run(
        [VENV_PYTHON, "-m", "pip", "show", "numpy", "h5py", "flask", "requests", "scipy"],
        capture_output=True, text=True
    )
    assert result.returncode == 0, f"Required packages are not installed in the venv: {result.stderr}"


def test_startup_script_starts_both_services_from_activated_venv():
    startup = "/app/startup.sh"
    assert os.path.isfile(startup), f"Startup script {startup} does not exist."
    assert os.access(startup, os.X_OK), f"Startup script {startup} is not executable."
    text = open(startup, encoding="utf-8").read()
    assert "/home/user/venv" in text and "activate" in text, \
        "startup.sh does not activate /home/user/venv."
    assert "/app/data_server.py" in text, "startup.sh does not start data_server.py."
    assert "/app/processor_api.py" in text, "startup.sh does not start processor_api.py."

    kill_service("/app/data_server.py")
    kill_service("/app/processor_api.py")
    try:
        result = subprocess.run(
            [startup], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            timeout=8, check=False
        )
    except subprocess.TimeoutExpired:
        pytest.fail("startup.sh did not exit gracefully after starting background services.")
    assert result.returncode == 0, f"startup.sh exited with status {result.returncode}."

    wait_for_url("http://127.0.0.1:8081/data")
    wait_for_url("http://127.0.0.1:8082/solve")

    for script_path in ("/app/data_server.py", "/app/processor_api.py"):
        pids = service_pids(script_path)
        assert pids, f"No running process found for {script_path}."
        activated = False
        for pid in pids:
            try:
                with open(f"/proc/{pid}/environ", "rb") as f:
                    environment = f.read().split(b"\0")
                if b"VIRTUAL_ENV=/home/user/venv" in environment:
                    activated = True
            except (FileNotFoundError, ProcessLookupError):
                pass
        assert activated, f"{script_path} was not launched from the activated virtual environment."


def test_solve_endpoint_correctness():
    expected_x = expected_for_file("/app/spectro_data.h5")
    try:
        response = requests.get("http://127.0.0.1:8082/solve", timeout=10)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to the processing API on port 8082: {exc}")

    assert response.status_code == 200, \
        f"Expected HTTP 200 OK, got {response.status_code}. Response: {response.text}"
    try:
        actual_x = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON. Response text: {response.text}")
    assert_vector(actual_x, expected_x)


def test_solve_downloads_and_processes_unseen_data():
    generation_script = r'''
import h5py
import numpy as np
import sys
rng = np.random.default_rng()
M = rng.normal(size=(47, 19))
b = rng.normal(size=47)
with h5py.File(sys.argv[1], 'w') as f:
    f.create_dataset('spectroscopy/raw', data=M)
    f.create_dataset('spectroscopy/vector', data=b)
'''
    with tempfile.NamedTemporaryFile(suffix=".h5", delete=False) as tmp:
        challenge_path = tmp.name
    try:
        generated = subprocess.run(
            [VENV_PYTHON, "-c", generation_script, challenge_path],
            capture_output=True, text=True
        )
        assert generated.returncode == 0, f"Could not generate challenge HDF5 file: {generated.stderr}"
        expected_x = expected_for_file(challenge_path)
        with open(challenge_path, "rb") as f:
            payload = f.read()

        kill_service("/app/data_server.py")

        class ChallengeHandler(BaseHTTPRequestHandler):
            request_count = 0

            def do_GET(self):
                if self.path != "/data":
                    self.send_response(404)
                    self.end_headers()
                    return
                type(self).request_count += 1
                self.send_response(200)
                self.send_header("Content-Type", "application/x-hdf5")
                self.send_header("Content-Length", str(len(payload)))
                self.end_headers()
                self.wfile.write(payload)

            def log_message(self, fmt, *args):
                pass

        server = None
        for _ in range(30):
            try:
                server = ThreadingHTTPServer(("127.0.0.1", 8081), ChallengeHandler)
                break
            except OSError:
                time.sleep(0.1)
        assert server is not None, "Could not start verifier challenge server on port 8081."
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            response = requests.get("http://127.0.0.1:8082/solve", timeout=15)
            assert response.status_code == 200, \
                f"Expected HTTP 200 for challenge data, got {response.status_code}: {response.text}"
            try:
                actual_x = response.json()
            except ValueError:
                pytest.fail(f"Challenge response is not valid JSON: {response.text}")
            assert ChallengeHandler.request_count >= 1, \
                "The processing API did not download the HDF5 data from port 8081."
            assert_vector(actual_x, expected_x)
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=2)
    finally:
        try:
            os.unlink(challenge_path)
        except FileNotFoundError:
            pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
