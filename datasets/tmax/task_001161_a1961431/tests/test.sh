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
import atexit
import json
import os
import random
import shutil
import signal
import socket
import stat
import subprocess
import time

import pytest
import requests

API_BASE_URL = "http://127.0.0.1:8000"
RUN_SCRIPT = "/home/user/run.sh"
RUST_BINARY = "/home/user/rust_emulator/target/release/rust_emulator"
VIDEO = "/app/demo.mp4"
RUN_PROCESS = None


def listener_pids(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local = fields[1]
                    state = fields[3]
                    if state == "0A" and int(local.rsplit(":", 1)[1], 16) == port:
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

    pids = set()
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        fd_dir = f"/proc/{pid}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(pid))
        except (FileNotFoundError, PermissionError):
            pass
    return pids


def kill_listeners():
    for port in (8000, 9000):
        for pid in listener_pids(port):
            try:
                os.kill(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
    time.sleep(0.5)
    for port in (8000, 9000):
        for pid in listener_pids(port):
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass


def stop_stack():
    global RUN_PROCESS
    if RUN_PROCESS is not None:
        try:
            os.killpg(RUN_PROCESS.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            RUN_PROCESS.wait(timeout=3)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(RUN_PROCESS.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        RUN_PROCESS = None
    kill_listeners()


atexit.register(stop_stack)


def wait_for_server(url, timeout=5):
    start = time.time()
    while time.time() - start < timeout:
        try:
            requests.get(url, timeout=1)
            return True
        except requests.RequestException:
            time.sleep(0.5)
    return False


def wait_for_tcp(port, timeout=60):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.5):
                return True
        except OSError:
            time.sleep(0.25)
    return False


def start_stack():
    global RUN_PROCESS
    stop_stack()
    shutil.rmtree("/home/user/rust_emulator/target/release", ignore_errors=True)
    RUN_PROCESS = subprocess.Popen(
        [RUN_SCRIPT],
        cwd="/home/user",
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    assert wait_for_tcp(9000, timeout=60), "Rust TCP server did not become available after running run.sh"
    assert wait_for_server(f"{API_BASE_URL}/status", timeout=60), "API server did not become available after running run.sh"
    assert os.path.isfile(RUST_BINARY), "run.sh did not build the Rust project in release mode"
    assert os.access(RUST_BINARY, os.X_OK), "Release Rust binary is not executable"

    pids = listener_pids(9000)
    assert pids, "No process is listening on TCP port 9000"
    expected = os.path.realpath(RUST_BINARY)
    executables = set()
    for pid in pids:
        try:
            executables.add(os.path.realpath(os.readlink(f"/proc/{pid}/exe")))
        except OSError:
            pass
    assert expected in executables, f"Port 9000 is not served by the built Rust release binary: {executables}"


def video_frame_count(path):
    output = subprocess.check_output([
        "ffprobe", "-v", "error", "-select_streams", "v:0",
        "-count_frames", "-show_entries", "stream=nb_read_frames",
        "-of", "default=nokey=1:noprint_wrappers=1", path,
    ], text=True).strip()
    return int(output)


def tcp_execute(command):
    with socket.create_connection(("127.0.0.1", 9000), timeout=3) as sock:
        sock.sendall((command + "\n").encode())
        data = b""
        while not data.endswith(b"\n"):
            chunk = sock.recv(128)
            if not chunk:
                break
            data += chunk
    return int(data.decode().strip())


def api_execute(command):
    response = requests.post(f"{API_BASE_URL}/execute", json={"command": command}, timeout=5)
    assert response.status_code == 200, response.text
    data = response.json()
    assert set(data) == {"result"}, f"Unexpected execute response: {data}"
    assert isinstance(data["result"], int) and not isinstance(data["result"], bool)
    return data["result"]


def test_run_script_exists_and_executable():
    script_path = "/home/user/run.sh"
    assert os.path.exists(script_path), f"Orchestration script missing at {script_path}"
    st = os.stat(script_path)
    assert bool(st.st_mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)), f"Script {script_path} is not executable"


def test_orchestration_builds_and_starts_required_services():
    start_stack()


def test_api_status_endpoint():
    assert wait_for_server(f"{API_BASE_URL}/status"), "API server did not become available"
    response = requests.get(f"{API_BASE_URL}/status", timeout=5)
    assert response.status_code == 200, f"Expected status 200, got {response.status_code}. Response: {response.text}"

    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")

    assert "frames" in data, f"Response JSON missing 'frames' key: {data}"
    assert data["frames"] == 150, f"Expected 150 frames, got {data['frames']}"
    assert data == {"frames": video_frame_count(VIDEO)}, f"Status does not report the video's actual frame count: {data}"


def test_api_execute_endpoint_mul():
    assert wait_for_server(f"{API_BASE_URL}/status"), "API server did not become available"
    payload = {"command": "MUL 7 8"}
    response = requests.post(f"{API_BASE_URL}/execute", json=payload, timeout=5)
    assert response.status_code == 200, f"Expected status 200, got {response.status_code}. Response: {response.text}"

    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")

    assert "result" in data, f"Response JSON missing 'result' key: {data}"
    assert data["result"] == 56, f"Expected result 56, got {data['result']}"


def test_api_execute_endpoint_add():
    assert wait_for_server(f"{API_BASE_URL}/status"), "API server did not become available"
    payload = {"command": "ADD 100 45"}
    response = requests.post(f"{API_BASE_URL}/execute", json=payload, timeout=5)
    assert response.status_code == 200, f"Expected status 200, got {response.status_code}. Response: {response.text}"

    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")

    assert "result" in data, f"Response JSON missing 'result' key: {data}"
    assert data["result"] == 145, f"Expected result 145, got {data['result']}"


def test_randomized_rust_and_api_commands():
    rng = random.SystemRandom()
    cases = []
    for op in ("ADD", "SUB", "MUL", "DIV"):
        a = rng.randint(20, 2000)
        b = rng.randint(2, 19)
        expected = {
            "ADD": a + b,
            "SUB": a - b,
            "MUL": a * b,
            "DIV": a // b,
        }[op]
        cases.append((f"{op} {a} {b}", expected))

    for command, expected in cases:
        assert tcp_execute(command) == expected, f"Rust emulator failed for {command}"
        assert api_execute(command) == expected, f"API failed for {command}"


def test_api_execute_depends_on_rust_tcp_server():
    pids = listener_pids(9000)
    assert pids
    for pid in pids:
        os.kill(pid, signal.SIGKILL)
    deadline = time.time() + 3
    while listener_pids(9000) and time.time() < deadline:
        time.sleep(0.1)
    assert not listener_pids(9000), "Could not stop the Rust TCP server"

    a = random.SystemRandom().randint(3001, 9000)
    expected = a + 37
    try:
        response = requests.post(
            f"{API_BASE_URL}/execute",
            json={"command": f"ADD {a} 37"},
            timeout=5,
        )
        valid_result = response.status_code == 200 and response.json().get("result") == expected
    except (requests.RequestException, ValueError):
        valid_result = False
    assert not valid_result, "The API produced a result even though the required Rust TCP server was unavailable"


def test_status_recounts_changed_video_on_restart():
    backup = "/tmp/demo.mp4.verifier-backup"
    stop_stack()
    shutil.copy2(VIDEO, backup)
    frame_target = random.SystemRandom().randint(11, 29)
    try:
        subprocess.check_call([
            "ffmpeg", "-v", "error", "-y", "-f", "lavfi",
            "-i", "color=c=blue:size=160x120:rate=23",
            "-frames:v", str(frame_target), "-pix_fmt", "yuv420p", VIDEO,
        ])
        actual = video_frame_count(VIDEO)
        assert actual == frame_target
        start_stack()
        response = requests.get(f"{API_BASE_URL}/status", timeout=5)
        assert response.status_code == 200
        assert response.json() == {"frames": actual}, "Status is hardcoded instead of counting /app/demo.mp4"
    finally:
        stop_stack()
        shutil.move(backup, VIDEO)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
