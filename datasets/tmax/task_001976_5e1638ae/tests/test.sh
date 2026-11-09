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
import ctypes
import os
import secrets
import socket
import subprocess
import tempfile

import cv2
import pytest
import requests

VIDEO_PATH = "/app/deployment_signal.mp4"
LIB_PATH = "/home/user/libdeploy.so"
PID_PATH = "/home/user/server.pid"


def extract_magic_number():
    cap = cv2.VideoCapture(VIDEO_PATH)
    assert cap.isOpened(), f"Could not open video: {VIDEO_PATH}"
    red_indices = []
    index = 0
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        # Lossy MP4 encoding perturbs channel values slightly, so classify the
        # uniformly red frames by tight channel bounds rather than exact bytes.
        b_mean = float(frame[:, :, 0].mean())
        g_mean = float(frame[:, :, 1].mean())
        r_mean = float(frame[:, :, 2].mean())
        if r_mean > 240 and g_mean < 15 and b_mean < 15:
            red_indices.append(index)
        index += 1
    cap.release()

    assert red_indices, "No red frames found in deployment video"
    assert red_indices == list(range(red_indices[0], red_indices[-1] + 1)), (
        "Red frames are not one continuous sequence"
    )
    return len(red_indices)


MAGIC_NUMBER = extract_magic_number()
# Preserve the known artifact assertion while deriving all behavioral answers
# from the artifact itself.
assert MAGIC_NUMBER == 145

rng = secrets.SystemRandom()
RANDOM_VALUES = set()
while len(RANDOM_VALUES) < 12:
    RANDOM_VALUES.add(rng.randint(-1_000_000, 1_000_000))
TEST_VALUES = [10, -45] + list(RANDOM_VALUES)


def read_server_pid():
    assert os.path.exists(PID_PATH), f"PID file missing: {PID_PATH} does not exist."
    with open(PID_PATH, "r") as f:
        pid_str = f.read().strip()
    assert pid_str.isdigit(), f"PID file does not contain a valid integer: '{pid_str}'"
    return int(pid_str)


def listening_socket_inodes(address="127.0.0.1", port=8000):
    wanted_addr = socket.inet_aton(address)[::-1].hex().upper()
    wanted_port = f"{port:04X}"
    inodes = set()
    with open("/proc/net/tcp", "r") as f:
        next(f)
        for line in f:
            fields = line.split()
            local_address, state, inode = fields[1], fields[3], fields[9]
            host_hex, port_hex = local_address.split(":")
            if host_hex == wanted_addr and port_hex == wanted_port and state == "0A":
                inodes.add(inode)
    return inodes


def pid_socket_inodes(pid):
    result = set()
    fd_dir = f"/proc/{pid}/fd"
    assert os.path.isdir(fd_dir), f"Process with PID {pid} is not running."
    for name in os.listdir(fd_dir):
        try:
            target = os.readlink(os.path.join(fd_dir, name))
        except OSError:
            continue
        if target.startswith("socket:[") and target.endswith("]"):
            result.add(target[8:-1])
    return result


def load_and_configure(path):
    lib = ctypes.CDLL(path)
    lib.get_magic_offset.argtypes = [ctypes.c_int]
    lib.get_magic_offset.restype = ctypes.c_int
    lib.invoke_offset.argtypes = [ctypes.c_int]
    lib.invoke_offset.restype = ctypes.c_int
    return lib


def assert_library_behavior(path):
    lib = load_and_configure(path)
    for value in TEST_VALUES:
        expected = value + MAGIC_NUMBER
        assert lib.get_magic_offset(value) == expected, (
            f"get_magic_offset({value}) did not return {expected}"
        )
        assert lib.invoke_offset(value) == expected, (
            f"invoke_offset({value}) did not return {expected}"
        )


def test_server_pid_exists():
    """Verify that the PID is live and is the process listening on the required address."""
    pid = read_server_pid()
    try:
        os.kill(pid, 0)
    except OSError:
        pytest.fail(f"Process with PID {pid} is not running.")

    listeners = listening_socket_inodes()
    assert listeners, "Nothing is listening exactly on 127.0.0.1:8000"
    assert listeners & pid_socket_inodes(pid), (
        f"PID {pid} does not own the listening socket on 127.0.0.1:8000"
    )


def test_shared_library_exists():
    """Verify that the submitted library exists, loads, exports both functions, and works."""
    assert os.path.exists(LIB_PATH), f"Shared library missing: {LIB_PATH} does not exist."
    assert os.path.isfile(LIB_PATH), f"Shared library is not a file: {LIB_PATH}."
    assert_library_behavior(LIB_PATH)


def test_sources_rebuild_and_work():
    """Compile the required C and Assembly sources independently and exercise the result."""
    asm_path = "/home/user/core.asm"
    c_path = "/home/user/wrapper.c"
    assert os.path.isfile(asm_path), f"Assembly source missing: {asm_path}"
    assert os.path.isfile(c_path), f"C source missing: {c_path}"

    with tempfile.TemporaryDirectory() as td:
        asm_obj = os.path.join(td, "core.o")
        c_obj = os.path.join(td, "wrapper.o")
        rebuilt = os.path.join(td, "libdeploy_rebuilt.so")
        subprocess.run(
            ["nasm", "-f", "elf64", asm_path, "-o", asm_obj],
            check=True, timeout=10, capture_output=True, text=True,
        )
        subprocess.run(
            ["gcc", "-fPIC", "-c", c_path, "-o", c_obj],
            check=True, timeout=10, capture_output=True, text=True,
        )
        subprocess.run(
            ["gcc", "-shared", "-o", rebuilt, c_obj, asm_obj],
            check=True, timeout=10, capture_output=True, text=True,
        )
        assert_library_behavior(rebuilt)


def test_api_status():
    url = "http://127.0.0.1:8000/status"
    try:
        response = requests.get(url, timeout=2)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to {url}: {e}")
    assert response.status_code == 200, (
        f"Expected HTTP 200, got {response.status_code}. Response: {response.text}"
    )
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response from {url} is not valid JSON. Response: {response.text}")
    assert data.get("status") == "ready", f"Expected status 'ready', got '{data.get('status')}'"
    assert data.get("magic") == MAGIC_NUMBER, (
        f"Expected magic {MAGIC_NUMBER}, got {data.get('magic')}"
    )


def test_api_compute():
    """Exercise fixed and unpredictable inputs, with expected values derived from the video."""
    for value in TEST_VALUES:
        expected = value + MAGIC_NUMBER
        url = f"http://127.0.0.1:8000/compute/{value}"
        try:
            response = requests.get(url, timeout=2)
        except requests.RequestException as e:
            pytest.fail(f"Failed to connect to {url}: {e}")
        assert response.status_code == 200, (
            f"Expected HTTP 200 for {url}, got {response.status_code}. Response: {response.text}"
        )
        try:
            data = response.json()
        except ValueError:
            pytest.fail(f"Response from {url} is not valid JSON. Response: {response.text}")
        assert "result" in data, f"Key 'result' missing in response from {url}. Response: {data}"
        assert data["result"] == expected, (
            f"Expected result {expected} for input {value}, got {data['result']}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
