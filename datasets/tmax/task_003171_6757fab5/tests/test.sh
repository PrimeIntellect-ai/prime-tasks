#!/bin/bash
set -e
mkdir -p /logs/verifier

# Stop ordinary pipeline processes that the agent may have left running so the
# verifier can execute the submitted artifacts itself.
if command -v pkill >/dev/null 2>&1; then
    pkill -f '/home/user/proxy.py' 2>/dev/null || true
    pkill -f '/home/user/ci_server.py' 2>/dev/null || true
fi
sleep 1

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import math
import os
import queue
import secrets
import signal
import socket
import subprocess
import threading
import time
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import pytest

HOME = "/home/user"


def wait_for_port(port, proc, timeout=8):
    deadline = time.time() + timeout
    while time.time() < deadline:
        assert proc.poll() is None, f"Process exited before opening port {port}"
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
            sock.settimeout(0.2)
            if sock.connect_ex(("127.0.0.1", port)) == 0:
                return
        time.sleep(0.05)
    pytest.fail(f"Timed out waiting for localhost:{port}")


def stop_process(proc):
    if proc is None or proc.poll() is not None:
        return
    try:
        os.killpg(proc.pid, signal.SIGTERM)
        proc.wait(timeout=3)
    except (ProcessLookupError, subprocess.TimeoutExpired):
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            pass


def start_python(path):
    return subprocess.Popen(
        ["python3", path],
        cwd=HOME,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )


@pytest.fixture(scope="session", autouse=True)
def execute_required_pipeline():
    build_path = os.path.join(HOME, "build.sh")
    lib_path = os.path.join(HOME, "libdevice.so")
    proxy_path = os.path.join(HOME, "proxy.py")
    results_path = os.path.join(HOME, "ci_results.json")

    assert os.path.isfile(build_path), f"Missing file: {build_path}"
    assert os.path.isfile(proxy_path), f"Missing file: {proxy_path}. The proxy script was not created."

    if os.path.exists(lib_path):
        os.remove(lib_path)
    build = subprocess.run(
        [build_path], cwd=HOME, capture_output=True, text=True, timeout=20
    )
    assert build.returncode == 0, f"build.sh failed:\n{build.stdout}\n{build.stderr}"
    assert os.path.exists(lib_path), f"Missing file: {lib_path}. The build script was not run or failed."

    if os.path.exists(results_path):
        os.remove(results_path)

    backend = proxy = None
    try:
        backend = start_python(os.path.join(HOME, "ci_server.py"))
        wait_for_port(9090, backend)
        proxy = start_python(proxy_path)
        wait_for_port(8080, proxy)

        emulator = subprocess.run(
            ["python3", os.path.join(HOME, "emulator.py")],
            cwd=HOME,
            capture_output=True,
            text=True,
            timeout=15,
        )
        assert emulator.returncode == 0, f"emulator.py failed:\n{emulator.stdout}\n{emulator.stderr}"
        assert "Sent successfully" in emulator.stdout, (
            f"emulator.py did not report a successful request:\n{emulator.stdout}\n{emulator.stderr}"
        )

        deadline = time.time() + 5
        while time.time() < deadline and not os.path.exists(results_path):
            time.sleep(0.05)
        assert os.path.exists(results_path), "The executed pipeline did not create ci_results.json"
    finally:
        stop_process(proxy)
        stop_process(backend)
        time.sleep(0.3)

    yield


def test_libdevice_compiled_and_linked():
    lib_path = "/home/user/libdevice.so"
    assert os.path.exists(lib_path), f"Missing file: {lib_path}. The build script was not run or failed."

    result = subprocess.run(['ldd', lib_path], capture_output=True, text=True)
    assert result.returncode == 0, f"Failed to run ldd on {lib_path}"
    assert "libm.so" in result.stdout, f"{lib_path} is not linked against libm.so. The build.sh script was likely not fixed correctly."

    lib = ctypes.CDLL(lib_path)
    lib.compute_sensor.argtypes = [ctypes.c_double]
    lib.compute_sensor.restype = ctypes.c_double
    for _ in range(4):
        value = (secrets.randbelow(2000001) - 1000000) / 100000.0
        actual = lib.compute_sensor(value)
        assert math.isclose(actual, math.cos(value), rel_tol=1e-12, abs_tol=1e-12), (
            f"compute_sensor({value}) returned {actual}, expected {math.cos(value)}"
        )


def test_proxy_script_exists():
    proxy_path = "/home/user/proxy.py"
    assert os.path.exists(proxy_path), f"Missing file: {proxy_path}. The proxy script was not created."


def test_ci_results_exists_and_correct():
    results_path = "/home/user/ci_results.json"
    assert os.path.exists(results_path), f"Missing file: {results_path}. The pipeline was not executed successfully."

    with open(results_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{results_path} does not contain valid JSON.")

    assert "proxy_header" in data, f"'proxy_header' key missing in {results_path}"
    assert data["proxy_header"] == "1", f"Expected 'proxy_header' to be '1', got '{data['proxy_header']}'. The proxy did not add the X-Proxy-Routed header correctly."
    assert "body" in data, f"'body' key missing in {results_path}"
    body = data["body"]
    assert "sensor_reading" in body, f"'sensor_reading' key missing in the body of {results_path}"
    assert body["sensor_reading"] == 1.0, f"Expected 'sensor_reading' to be 1.0, got {body['sensor_reading']}"


def test_proxy_forwards_emulator_and_unpredictable_body_exactly():
    received = queue.Queue()

    class CaptureHandler(BaseHTTPRequestHandler):
        def do_POST(self):
            length = int(self.headers.get("Content-Length", "0"))
            body = self.rfile.read(length)
            received.put({"body": body, "header": self.headers.get("X-Proxy-Routed")})
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"OK")

        def log_message(self, *args):
            pass

    backend = ThreadingHTTPServer(("127.0.0.1", 9090), CaptureHandler)
    thread = threading.Thread(target=backend.serve_forever, daemon=True)
    thread.start()
    proxy = None
    try:
        proxy = start_python(os.path.join(HOME, "proxy.py"))
        wait_for_port(8080, proxy)

        emulator = subprocess.run(
            ["python3", os.path.join(HOME, "emulator.py")],
            cwd=HOME,
            capture_output=True,
            text=True,
            timeout=15,
        )
        assert emulator.returncode == 0
        first = received.get(timeout=5)
        assert first["header"] == "1"
        assert json.loads(first["body"].decode("utf-8"))["sensor_reading"] == 1.0

        unpredictable = secrets.token_bytes(97)
        request = urllib.request.Request(
            "http://127.0.0.1:8080/audit-" + secrets.token_hex(12),
            data=unpredictable,
            method="POST",
            headers={"Content-Type": "application/octet-stream"},
        )
        with urllib.request.urlopen(request, timeout=8) as response:
            assert response.status == 200

        second = received.get(timeout=5)
        assert second["header"] == "1", "Proxy did not add X-Proxy-Routed: 1"
        assert second["body"] == unpredictable, "Proxy did not forward the request body exactly"
    finally:
        stop_process(proxy)
        backend.shutdown()
        backend.server_close()
        thread.join(timeout=2)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
