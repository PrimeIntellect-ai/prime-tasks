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
import os
import secrets
import signal
import subprocess
import time

import pytest
import requests

URL = "http://127.0.0.1:8080/anomalies"
HEADERS = {"Authorization": "Bearer trace-mgr-77"}


def get_listener_pid():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if fields[1].split(":")[-1].upper() == "1F90" and fields[3] == "0A":
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    return int(entry)
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
    pytest.fail("Could not identify the process listening on port 8080")


def capture_process(pid):
    with open(f"/proc/{pid}/cmdline", "rb") as f:
        argv = [os.fsdecode(x) for x in f.read().split(b"\0") if x]
    assert argv, "Listening process has an empty command line"
    cwd = os.readlink(f"/proc/{pid}/cwd")
    exe = os.readlink(f"/proc/{pid}/exe")
    with open(f"/proc/{pid}/environ", "rb") as f:
        entries = f.read().split(b"\0")
    env = os.environ.copy()
    for entry in entries:
        if b"=" in entry:
            key, value = entry.split(b"=", 1)
            env[os.fsdecode(key)] = os.fsdecode(value)
    return argv, cwd, exe, env


def assert_cpp_ffmpeg_artifact(exe):
    with open(exe, "rb") as f:
        image = f.read()
    assert image.startswith(b"\x7fELF"), "The listening service must be a compiled native executable"
    assert b"ffmpeg" in image.lower(), "The service executable does not contain an ffmpeg invocation"


def stop_process(pid):
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    for _ in range(50):
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            return
        time.sleep(0.1)
    try:
        os.kill(pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    time.sleep(0.2)


def start_process(argv, cwd, env):
    subprocess.Popen(
        argv,
        cwd=cwd,
        env=env,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    last_error = None
    for _ in range(150):
        try:
            response = requests.get(URL, headers=HEADERS, timeout=1)
            if response.status_code == 200:
                return response
        except requests.RequestException as exc:
            last_error = exc
        time.sleep(0.1)
    pytest.fail(f"Service did not restart on port 8080: {last_error}")


def make_dynamic_fixture():
    names = [f"dyn_{secrets.token_hex(8)}" for _ in range(3)]
    with open("/home/user/baseline_config.csv", "w") as f:
        f.write("timestamp_sec,config_id\n")
        f.write(f"0,{names[0]}\n2,{names[1]}\n4,{names[2]}\n")

    frame_numbers = [
        secrets.choice(range(3, 8)),
        secrets.choice(range(17, 24)),
        secrets.choice(range(35, 40)),
    ]
    command = [
        "ffmpeg", "-y", "-loglevel", "error",
        "-f", "rawvideo", "-pix_fmt", "gray", "-s", "320x240", "-r", "10",
        "-i", "pipe:0", "-an", "-c:v", "libx264", "-preset", "ultrafast",
        "-crf", "0", "-pix_fmt", "yuv420p", "/app/rack_monitor.mp4",
    ]
    proc = subprocess.Popen(command, stdin=subprocess.PIPE)
    dark = bytes([0]) * (320 * 240)
    bright = bytes([255]) * (320 * 240)
    for frame in range(45):
        proc.stdin.write(bright if frame in frame_numbers else dark)
    proc.stdin.close()
    rc = proc.wait()
    assert rc == 0, "Failed to create randomized verification video"

    return [
        {"time_sec": frame_numbers[0] / 10.0, "config_id": names[0]},
        {"time_sec": frame_numbers[1] / 10.0, "config_id": names[1]},
        {"time_sec": frame_numbers[2] / 10.0, "config_id": names[2]},
    ]


def assert_anomalies(data, expected):
    assert isinstance(data, list), f"Expected response to be a JSON array, got {type(data).__name__}"
    assert len(data) == len(expected), f"Expected {len(expected)} anomalies, got {len(data)}"
    for i, wanted in enumerate(expected):
        actual = data[i]
        assert isinstance(actual, dict), f"Anomaly {i} is not an object"
        assert "time_sec" in actual, f"Missing 'time_sec' in anomaly {i}"
        assert "config_id" in actual, f"Missing 'config_id' in anomaly {i}"
        assert isinstance(actual["time_sec"], (int, float)) and not isinstance(actual["time_sec"], bool)
        assert abs(actual["time_sec"] - wanted["time_sec"]) < 0.05, \
            f"Anomaly {i} time_sec mismatch: expected {wanted['time_sec']}, got {actual['time_sec']}"
        assert actual["config_id"] == wanted["config_id"], \
            f"Anomaly {i} config_id mismatch: expected {wanted['config_id']}, got {actual['config_id']}"


def test_service_uses_csv_and_video():
    try:
        response = requests.get(URL, headers=HEADERS, timeout=5)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to the service at {URL}: {exc}")

    assert response.status_code == 200, \
        f"Expected HTTP 200, got {response.status_code}. Response: {response.text}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")

    original_expected = [
        {"time_sec": 2.3, "config_id": "cfg_update_1"},
        {"time_sec": 5.7, "config_id": "cfg_update_2"},
        {"time_sec": 8.1, "config_id": "cfg_final"},
    ]
    assert_anomalies(data, original_expected)

    pid = get_listener_pid()
    argv, cwd, exe, env = capture_process(pid)
    assert_cpp_ffmpeg_artifact(exe)

    dynamic_expected = make_dynamic_fixture()
    stop_process(pid)
    response = start_process(argv, cwd, env)
    assert response.status_code == 200, \
        f"Expected HTTP 200 after restart, got {response.status_code}. Response: {response.text}"
    try:
        dynamic_data = response.json()
    except ValueError:
        pytest.fail(f"Response after restart is not valid JSON: {response.text}")
    assert_anomalies(dynamic_data, dynamic_expected)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
