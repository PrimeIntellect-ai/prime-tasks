#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import signal
import stat
import subprocess
import time
import uuid

import pytest

HOME = "/home/user"
PROFILE = f"{HOME}/.obs_profile"
TARGET = f"{HOME}/obs_target.py"
COLLECTOR = f"{HOME}/collector.py"
DATA_DIR = f"{HOME}/data_dir"
LOG_DIR = f"{HOME}/dashboard_logs"
METRICS = f"{LOG_DIR}/metrics.json"
EXPECTED_KEYS = {"target_pid", "target_status", "data_dir_kb", "quota_exceeded"}


def load_metrics():
    assert os.path.exists(METRICS), f"File {METRICS} does not exist."
    with open(METRICS, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Could not parse JSON from {METRICS}")


def directory_kb(path):
    total = 0
    for root, dirs, files in os.walk(path):
        for name in files:
            item = os.path.join(root, name)
            if not os.path.islink(item):
                total += os.path.getsize(item)
    return total // 1024


def run_collector(proc_name, quota):
    if os.path.exists(METRICS):
        os.unlink(METRICS)
    env = os.environ.copy()
    env["OBS_PROC_NAME"] = proc_name
    env["OBS_MAX_DISK_KB"] = str(quota)
    result = subprocess.run(
        ["python3", COLLECTOR], env=env, capture_output=True, text=True, timeout=10
    )
    assert result.returncode == 0, (
        f"collector.py failed with exit code {result.returncode}: "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    return load_metrics()


def test_obs_profile_exists_and_content():
    path = PROFILE
    assert os.path.exists(path), f"File {path} does not exist."
    with open(path, "r") as f:
        content = f.read()
    assert "OBS_MAX_DISK_KB=1000" in content, "OBS_MAX_DISK_KB=1000 not found in .obs_profile"
    assert "OBS_PROC_NAME=obs_target.py" in content, "OBS_PROC_NAME=obs_target.py not found in .obs_profile"

    result = subprocess.run(
        ["bash", "-c", 'source /home/user/.obs_profile && printf "%s\\n%s" "$OBS_MAX_DISK_KB" "$OBS_PROC_NAME"'],
        capture_output=True, text=True, timeout=5
    )
    assert result.returncode == 0, f"Could not source {path}: {result.stderr}"
    assert result.stdout.splitlines() == ["1000", "obs_target.py"], (
        ".obs_profile must set OBS_MAX_DISK_KB=1000 and OBS_PROC_NAME=obs_target.py"
    )


def test_obs_target_file_exists():
    path = TARGET
    assert os.path.exists(path), f"File {path} does not exist."
    assert os.path.isfile(path), f"{path} is not a regular file."


def test_obs_target_is_a_long_running_sleeping_script():
    proc = subprocess.Popen(["python3", TARGET], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    try:
        time.sleep(1.0)
        assert proc.poll() is None, "obs_target.py exited instead of looping indefinitely."
        with open(f"/proc/{proc.pid}/stat", "r") as f:
            fields1 = f.read().split()
        ticks1 = int(fields1[13]) + int(fields1[14])
        time.sleep(1.0)
        assert proc.poll() is None, "obs_target.py did not remain running."
        with open(f"/proc/{proc.pid}/stat", "r") as f:
            fields2 = f.read().split()
        ticks2 = int(fields2[13]) + int(fields2[14])
        assert fields2[2] in {"S", "I"}, "obs_target.py is not sleeping while idle."
        assert ticks2 - ticks1 <= 10, "obs_target.py is busy-looping rather than sleeping."
    finally:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait()


def test_data_dir_and_dummy_file():
    path = f"{DATA_DIR}/dummy.dat"
    assert os.path.exists(path), f"File {path} does not exist."
    size = os.path.getsize(path)
    assert size == 2097152, f"Expected {path} to be exactly 2097152 bytes (2MB), got {size} bytes."


def test_dashboard_logs_permissions():
    path = LOG_DIR
    assert os.path.exists(path), f"Directory {path} does not exist."
    assert os.path.isdir(path), f"{path} is not a directory."
    stat_info = os.stat(path)
    permissions = stat.S_IMODE(stat_info.st_mode)
    assert permissions == 0o750, f"Expected permissions 0o750 for {path}, got {oct(permissions)}"


def test_collector_file_exists():
    path = COLLECTOR
    assert os.path.exists(path), f"File {path} does not exist."
    assert os.path.isfile(path), f"{path} is not a regular file."


def test_process_running_and_metrics_json_content():
    assert os.path.exists(METRICS), f"File {METRICS} does not exist."

    pid_check = subprocess.run(["pgrep", "-f", "obs_target.py"], capture_output=True, text=True)
    assert pid_check.returncode == 0, "obs_target.py is not running in the background."
    pids = pid_check.stdout.strip().split("\n")
    actual_pid = int(pids[0])

    data = load_metrics()
    assert "target_pid" in data, "Key 'target_pid' missing from metrics.json"
    assert data["target_pid"] == actual_pid, f"Expected target_pid {actual_pid}, got {data['target_pid']}"
    assert "target_status" in data, "Key 'target_status' missing from metrics.json"
    assert data["target_status"] == "running", f"Expected target_status 'running', got '{data['target_status']}'"
    assert "data_dir_kb" in data, "Key 'data_dir_kb' missing from metrics.json"
    assert isinstance(data["data_dir_kb"], int), "data_dir_kb must be an integer"
    assert data["data_dir_kb"] >= 2048, f"Expected data_dir_kb >= 2048, got {data['data_dir_kb']}"
    assert "quota_exceeded" in data, "Key 'quota_exceeded' missing from metrics.json"
    assert data["quota_exceeded"] is True, f"Expected quota_exceeded to be True, got {data['quota_exceeded']}"


def test_collector_executes_and_uses_runtime_inputs():
    token = uuid.uuid4().hex
    probe_name = f"obs_probe_{token}.py"
    probe_path = os.path.join(HOME, probe_name)
    extra_path = os.path.join(DATA_DIR, f"probe_{token}.dat")

    with open(probe_path, "w") as f:
        f.write("import time\nwhile True:\n    time.sleep(1)\n")
    with open(extra_path, "wb") as f:
        f.truncate(317 * 1024)

    probe = subprocess.Popen(["python3", probe_path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        time.sleep(0.4)
        assert probe.poll() is None, "Verifier probe process failed to start."
        expected_kb = directory_kb(DATA_DIR)

        data = run_collector(probe_name, expected_kb)
        assert set(data.keys()) == EXPECTED_KEYS, f"metrics.json must contain exactly {EXPECTED_KEYS}"
        assert type(data["target_pid"]) is int, "target_pid must be an integer"
        assert data["target_pid"] == probe.pid, "collector did not find the process named by OBS_PROC_NAME"
        assert data["target_status"] == "running"
        assert type(data["data_dir_kb"]) is int, "data_dir_kb must be an integer"
        assert data["data_dir_kb"] == expected_kb, "collector did not calculate the current data directory size"
        assert data["quota_exceeded"] is False, "quota_exceeded must be false when size equals quota"

        data = run_collector(probe_name, expected_kb - 1)
        assert set(data.keys()) == EXPECTED_KEYS, f"metrics.json must contain exactly {EXPECTED_KEYS}"
        assert data["target_pid"] == probe.pid
        assert data["target_status"] == "running"
        assert data["data_dir_kb"] == expected_kb
        assert data["quota_exceeded"] is True, "quota_exceeded must be true only when size is greater than quota"
    finally:
        if probe.poll() is None:
            probe.terminate()
            try:
                probe.wait(timeout=3)
            except subprocess.TimeoutExpired:
                probe.kill()
                probe.wait()
        for path in (extra_path, probe_path):
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass

    result = subprocess.run(
        ["bash", "-c", "source /home/user/.obs_profile && python3 /home/user/collector.py"],
        capture_output=True, text=True, timeout=10
    )
    assert result.returncode == 0, f"collector.py failed with the configured profile: {result.stderr}"
    final_data = load_metrics()
    assert set(final_data.keys()) == EXPECTED_KEYS
    assert final_data["target_status"] == "running"
    assert final_data["data_dir_kb"] == directory_kb(DATA_DIR)
    assert final_data["quota_exceeded"] is (final_data["data_dir_kb"] > 1000)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
