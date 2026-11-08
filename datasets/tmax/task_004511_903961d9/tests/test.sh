#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib
import importlib.machinery
import json
import math
import os
import signal
import socket
import subprocess
import sys
import time
import urllib.request

import cv2
import numpy as np
import pytest

PROJECT = "/home/user/project"
SRC = PROJECT + "/src"
TESTS = PROJECT + "/tests"
LOG = TESTS + "/api_log.json"
VIDEO = "/app/video.mp4"


def expected_video_data():
    cap = cv2.VideoCapture(VIDEO)
    assert cap.isOpened(), "Could not open the video fixture"
    values = []
    signatures = []
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        flat = frame.reshape(-1)
        total = int(frame.sum(dtype=np.uint64))
        values.append(total / int(frame.size))
        n = int(flat.size)
        middle = (n // 6) * 3
        signatures.append([
            n,
            int(flat[0]) + int(flat[1]) + int(flat[2]),
            int(flat[middle]) + int(flat[middle + 1]) + int(flat[middle + 2]),
            int(flat[n - 3]) + int(flat[n - 2]) + int(flat[n - 1]),
        ])
    cap.release()
    assert values, "The video fixture contains no decodable frames"
    return values, signatures


def assert_payload_correct(data):
    expected, _ = expected_video_data()
    assert "video" in data, "JSON payload missing 'video' key."
    assert data["video"] == VIDEO, f"Expected video path '{VIDEO}', got {data['video']}"
    assert "frames_brightness" in data, "JSON payload missing 'frames_brightness' key."
    actual = data["frames_brightness"]
    assert isinstance(actual, list), "'frames_brightness' should be a list."
    assert len(actual) > 0, "'frames_brightness' list is empty."
    assert all(isinstance(x, (int, float)) for x in actual), "All brightness values must be numbers."
    assert all(not isinstance(x, bool) and math.isfinite(float(x)) for x in actual), "Brightness values must be finite numbers."
    assert len(actual) == len(expected), f"Expected {len(expected)} frame values, got {len(actual)}"
    for i, (got, want) in enumerate(zip(actual, expected)):
        assert math.isclose(float(got), want, rel_tol=0.0, abs_tol=1e-9), \
            f"Incorrect brightness for frame {i}: got {got}, expected {want}"


def port_open(port):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.settimeout(0.2)
        return sock.connect_ex(("127.0.0.1", port)) == 0


def wait_for_port(port, proc, timeout=8.0):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if proc.poll() is not None:
            out, err = proc.communicate()
            pytest.fail(f"Process for port {port} exited early. stdout={out!r} stderr={err!r}")
        if port_open(port):
            return
        time.sleep(0.05)
    pytest.fail(f"Timed out waiting for port {port}")


def stop_process(proc):
    if proc.poll() is None:
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
            proc.wait(timeout=3)


def test_project_structure():
    assert os.path.isdir(SRC), "Directory /home/user/project/src/ does not exist."
    assert os.path.isdir(SRC + "/rust_ext"), "Directory /home/user/project/src/rust_ext/ does not exist."
    assert os.path.isdir(TESTS), "Directory /home/user/project/tests/ does not exist."
    assert os.path.isfile(SRC + "/process_video.py"), "process_video.py is missing in /home/user/project/src/"
    assert os.path.isfile(TESTS + "/mock_api.py"), "mock_api.py is missing in /home/user/project/tests/"
    assert os.path.isfile(TESTS + "/proxy.py"), "proxy.py is missing in /home/user/project/tests/"
    assert os.path.isfile(PROJECT + "/run_ci.sh"), "run_ci.sh is missing in /home/user/project/"
    assert os.path.isfile(SRC + "/rust_ext/Cargo.toml"), "Rust Cargo.toml is missing"
    assert os.path.isfile(SRC + "/rust_ext/src/lib.rs"), "Rust src/lib.rs is missing"


def test_native_rust_extension():
    sys.path.insert(0, SRC)
    try:
        mod = importlib.import_module("fast_video_utils")
    finally:
        sys.path.pop(0)
    module_path = os.path.realpath(mod.__file__)
    assert any(module_path.endswith(suffix) for suffix in importlib.machinery.EXTENSION_SUFFIXES), \
        f"fast_video_utils is not a native Python extension: {module_path}"
    with open(module_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "fast_video_utils is not an ELF shared library"
    cases = [
        [0, 0, 0],
        [255, 255, 255],
        [1, 2, 3, 4, 5, 6],
        [((i * 73) + 19) % 256 for i in range(10003)],
    ]
    for values in cases:
        want = sum(values) / len(values)
        got = mod.calculate_brightness(values)
        assert isinstance(got, float)
        assert math.isclose(got, want, rel_tol=0.0, abs_tol=1e-12), \
            f"Rust calculate_brightness returned {got}, expected {want}"


def test_pipeline_execution_and_metrics():
    ci_script_path = PROJECT + "/run_ci.sh"
    assert os.access(ci_script_path, os.X_OK), "run_ci.sh is not executable"
    if os.path.exists(LOG):
        os.remove(LOG)
    start_time = time.time()
    result = subprocess.run(["bash", ci_script_path], cwd=PROJECT, capture_output=True, text=True, timeout=30)
    agent_time = time.time() - start_time
    assert result.returncode == 0, \
        f"run_ci.sh failed with return code {result.returncode}. stderr: {result.stderr}"
    assert os.path.exists(LOG), f"Log file {LOG} was not created by the mock API."
    with open(LOG, "r") as f:
        try:
            agent_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("api_log.json does not contain valid JSON.")
    assert_payload_correct(agent_data)
    assert agent_time < 10.0, \
        f"Agent execution time {agent_time:.2f}s is too slow. Rust optimization should make it faster."
    time.sleep(0.4)
    assert not port_open(8080), "run_ci.sh did not shut down the reverse proxy"
    assert not port_open(9090), "run_ci.sh did not shut down the mock API"


def test_proxy_mock_and_process_uses_rust_on_video_frames(tmp_path):
    assert not port_open(8080) and not port_open(9090), "Required test ports are already occupied"
    if os.path.exists(LOG):
        os.remove(LOG)

    mock = subprocess.Popen(
        [sys.executable, TESTS + "/mock_api.py"], cwd=TESTS,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, start_new_session=True)
    proxy = None
    try:
        wait_for_port(9090, mock)
        proxy = subprocess.Popen(
            [sys.executable, TESTS + "/proxy.py"], cwd=TESTS,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, start_new_session=True)
        wait_for_port(8080, proxy)

        probe = {"probe": "through-proxy", "number": 7319}
        request = urllib.request.Request(
            "http://127.0.0.1:8080/report",
            data=json.dumps(probe).encode("utf-8"),
            headers={"Content-Type": "application/json"},
            method="POST")
        with urllib.request.urlopen(request, timeout=5) as response:
            assert 200 <= response.status < 300
        deadline = time.time() + 3
        while time.time() < deadline and not os.path.exists(LOG):
            time.sleep(0.05)
        assert os.path.exists(LOG), "The proxied request was not logged by mock_api.py"
        with open(LOG) as f:
            assert json.load(f) == probe, "The proxy did not forward the request body unchanged"
        os.remove(LOG)

        marker = str(tmp_path / "rust_calls.json")
        runner = str(tmp_path / "instrument_process.py")
        with open(runner, "w") as f:
            f.write(r'''import importlib
import json
import runpy
import sys

src, script, marker = sys.argv[1:]
sys.path.insert(0, src)
mod = importlib.import_module("fast_video_utils")
original = mod.calculate_brightness
calls = []
def wrapped(data):
    n = len(data)
    if n < 3 or n % 3:
        raise AssertionError("calculate_brightness did not receive flattened RGB/BGR pixels")
    middle = (n // 6) * 3
    calls.append([n,
                  int(data[0]) + int(data[1]) + int(data[2]),
                  int(data[middle]) + int(data[middle + 1]) + int(data[middle + 2]),
                  int(data[n - 3]) + int(data[n - 2]) + int(data[n - 1])])
    return original(data)
mod.calculate_brightness = wrapped
try:
    runpy.run_path(script, run_name="__main__")
except SystemExit as exc:
    if exc.code not in (None, 0):
        raise
with open(marker, "w") as out:
    json.dump(calls, out)
''')
        result = subprocess.run(
            [sys.executable, runner, SRC, SRC + "/process_video.py", marker],
            cwd=SRC, capture_output=True, text=True, timeout=15)
        assert result.returncode == 0, \
            f"Instrumented process_video.py failed. stdout={result.stdout!r} stderr={result.stderr!r}"
        assert os.path.exists(marker), "process_video.py did not complete through the instrumented Rust module"
        with open(marker) as f:
            calls = json.load(f)
        expected_values, expected_signatures = expected_video_data()
        assert calls == expected_signatures, \
            "process_video.py did not call Rust calculate_brightness once for each extracted video frame"
        assert os.path.exists(LOG), "process_video.py did not send its payload through the running services"
        with open(LOG) as f:
            payload = json.load(f)
        assert_payload_correct(payload)
        assert len(payload["frames_brightness"]) == len(expected_values)
    finally:
        if proxy is not None:
            stop_process(proxy)
        stop_process(mock)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
