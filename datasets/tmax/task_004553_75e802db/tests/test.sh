#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import gzip
import json
import os
import pwd
import re
import signal
import subprocess
import time

import pytest

BASE_DIR = "/home/user/observability"
LOGS_DIR = os.path.join(BASE_DIR, "logs")
GENERATOR = os.path.join(BASE_DIR, "telemetry_generator.py")
DEPLOY = os.path.join(BASE_DIR, "deploy.py")
VERSION = os.path.join(BASE_DIR, "version.txt")
STATE = os.path.join(BASE_DIR, "logrotate.state")
SERVICE = "/home/user/.config/systemd/user/telemetry.service"


def user_preexec():
    account = pwd.getpwnam("user")
    os.setgid(account.pw_gid)
    os.setuid(account.pw_uid)


def generator_pids():
    result = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            with open(f"/proc/{entry}/cmdline", "rb") as f:
                args = [part.decode(errors="replace") for part in f.read().split(b"\0") if part]
            if any(arg == GENERATOR or arg.endswith("/telemetry_generator.py") for arg in args):
                result.append(int(entry))
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return result


def stop_generators():
    pids = generator_pids()
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while time.time() < deadline and generator_pids():
        time.sleep(0.05)
    for pid in generator_pids():
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def read_json_lines(path):
    with open(path, "r") as f:
        return [json.loads(line) for line in f if line.strip()]


def validate_record(data, expected_version=None):
    assert set(data) == {"timestamp", "cpu", "version"}, f"Wrong telemetry keys: {data}"
    assert type(data["timestamp"]) in (int, float), "timestamp must be numeric"
    assert type(data["cpu"]) is int, "cpu must be an integer"
    assert 0 <= data["cpu"] <= 100, "cpu must be between 0 and 100"
    assert isinstance(data["version"], str), "version must be a string"
    if expected_version is not None:
        assert data["version"] == expected_version


def test_directories_exist():
    assert os.path.isdir(BASE_DIR), f"{BASE_DIR} does not exist"
    assert os.path.isdir(LOGS_DIR), f"{LOGS_DIR} does not exist"


def test_files_exist():
    expected_files = [GENERATOR, SERVICE, os.path.join(BASE_DIR, "logrotate.conf"), DEPLOY, VERSION]
    for filepath in expected_files:
        assert os.path.isfile(filepath), f"File missing: {filepath}"


def test_version_file_content():
    with open(VERSION, "r") as f:
        version = f.read().strip()
    assert version == "v1.2", f"Expected version.txt to be 'v1.2', got '{version}'"


def test_systemd_service_content():
    with open(SERVICE, "r") as f:
        content = f.read()
    assert "ExecStart=" in content, "Service file missing ExecStart directive"
    assert "telemetry_generator.py" in content, "Service file missing script reference in ExecStart"
    assert "Restart=always" in content or "Restart=on-failure" in content, "Service missing restart condition (Restart=always or Restart=on-failure)"
    assert "WorkingDirectory=/home/user/observability" in content, "Service missing WorkingDirectory=/home/user/observability"


def test_logrotate_conf_content():
    logrotate_path = os.path.join(BASE_DIR, "logrotate.conf")
    with open(logrotate_path, "r") as f:
        content = f.read()
    assert re.search(r"size\s+(1k|1024)", content, re.IGNORECASE) or "size=1k" in content.replace(" ", ""), "logrotate.conf missing size 1k requirement"
    assert "rotate 3" in content, "logrotate.conf missing 'rotate 3'"
    assert "compress" in content, "logrotate.conf missing 'compress'"


def test_telemetry_generator_behavior():
    stop_generators()
    os.makedirs(LOGS_DIR, exist_ok=True)
    os.chmod(LOGS_DIR, 0o777)
    telemetry = os.path.join(LOGS_DIR, "telemetry.log")
    if os.path.exists(telemetry):
        os.remove(telemetry)
    if os.path.exists(VERSION):
        os.remove(VERSION)

    env = os.environ.copy()
    env["HOME"] = "/home/user"
    proc = subprocess.Popen(
        ["python3", GENERATOR], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        env=env, preexec_fn=user_preexec
    )
    try:
        deadline = time.time() + 2.0
        lines = []
        while time.time() < deadline:
            if proc.poll() is not None:
                pytest.fail(f"telemetry_generator.py exited early with status {proc.returncode}")
            if os.path.exists(telemetry):
                lines = read_json_lines(telemetry)
                if len(lines) >= 3:
                    break
            time.sleep(0.03)
        assert len(lines) >= 3, "Generator did not flush telemetry records while running"

        with open(VERSION, "w") as f:
            f.write("changed-after-start")
        deadline = time.time() + 1.0
        while time.time() < deadline:
            lines = read_json_lines(telemetry)
            if len(lines) >= 6:
                break
            time.sleep(0.03)
        assert len(lines) >= 6, "Generator did not produce records at the required cadence"
        for record in lines:
            validate_record(record, "v0.0")
        gaps = [b["timestamp"] - a["timestamp"] for a, b in zip(lines, lines[1:])]
        assert all(0.04 <= gap <= 0.5 for gap in gaps[-4:]), f"Unexpected telemetry cadence: {gaps}"
    finally:
        try:
            proc.terminate()
            proc.wait(timeout=2)
        except (ProcessLookupError, subprocess.TimeoutExpired):
            try:
                proc.kill()
            except ProcessLookupError:
                pass
        stop_generators()


def test_execute_deploy_and_validate_rotations():
    stop_generators()
    os.makedirs(LOGS_DIR, exist_ok=True)
    os.chmod(LOGS_DIR, 0o777)
    for name in os.listdir(LOGS_DIR):
        path = os.path.join(LOGS_DIR, name)
        if os.path.isfile(path) or os.path.islink(path):
            os.remove(path)
    for path in (VERSION, STATE):
        if os.path.exists(path):
            os.remove(path)

    env = os.environ.copy()
    env["HOME"] = "/home/user"
    start = time.monotonic()
    proc = subprocess.Popen(
        ["python3", DEPLOY], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        env=env, preexec_fn=user_preexec
    )
    observations = {v: [] for v in ("v1.0", "v1.1", "v1.2")}
    try:
        deadline = time.monotonic() + 15
        while proc.poll() is None and time.monotonic() < deadline:
            try:
                with open(VERSION, "r") as f:
                    version = f.read().strip()
            except FileNotFoundError:
                version = None
            if version in observations and generator_pids():
                observations[version].append(time.monotonic())
            time.sleep(0.05)
        if proc.poll() is None:
            proc.kill()
            proc.wait(timeout=2)
            pytest.fail("deploy.py did not complete within 15 seconds")
        assert proc.returncode == 0, f"deploy.py exited with status {proc.returncode}"
    finally:
        if proc.poll() is None:
            proc.kill()

    elapsed = time.monotonic() - start
    assert elapsed >= 5.5, f"deploy.py did not perform three 2-second deployment stages ({elapsed:.2f}s)"
    for version, seen in observations.items():
        assert seen, f"No running telemetry generator was observed during deployment of {version}"
        assert seen[-1] - seen[0] >= 1.4, f"Deployment stage {version} was not held for about 2 seconds"

    with open(VERSION, "r") as f:
        assert f.read().strip() == "v1.2"

    telemetry = os.path.join(LOGS_DIR, "telemetry.log")
    assert os.path.isfile(telemetry), "telemetry.log missing after deploy.py"
    size_before = os.path.getsize(telemetry)
    time.sleep(0.35)
    size_after = os.path.getsize(telemetry)
    assert generator_pids(), "deploy.py did not leave the final telemetry generator running"
    assert size_after > size_before, "Final telemetry.log is not receiving live, flushed records"

    compressed = sorted(os.path.join(LOGS_DIR, n) for n in os.listdir(LOGS_DIR) if n.endswith(".gz"))
    assert len(compressed) == 3, f"Expected exactly 3 compressed rotations, found {len(compressed)}"

    all_records = []
    for path in compressed:
        with gzip.open(path, "rt") as f:
            records = [json.loads(line) for line in f if line.strip()]
        assert records, f"Rotated log is empty: {path}"
        for record in records:
            validate_record(record)
        all_records.extend(records)

    active_records = read_json_lines(telemetry)
    assert active_records, "Active telemetry.log is empty"
    for record in active_records:
        validate_record(record, "v1.2")
    all_records.extend(active_records)
    versions = {record["version"] for record in all_records}
    assert {"v1.0", "v1.1", "v1.2"}.issubset(versions), f"Rotated logs do not show every deployment stage: {versions}"


def test_logs_and_rotation():
    log_files = os.listdir(LOGS_DIR)
    assert "telemetry.log" in log_files, "telemetry.log missing from logs directory"
    compressed_logs = [f for f in log_files if f.endswith(".gz")]
    assert len(compressed_logs) > 0, "No compressed rotated logs found. deploy.py may not have successfully run logrotate."


def test_telemetry_json_format():
    telemetry_path = os.path.join(LOGS_DIR, "telemetry.log")
    with open(telemetry_path, "r") as f:
        lines = f.readlines()
    for line in lines[-5:]:
        line = line.strip()
        if not line:
            continue
        try:
            data = json.loads(line)
            assert "timestamp" in data, "JSON log missing 'timestamp' key"
            assert "cpu" in data, "JSON log missing 'cpu' key"
            assert "version" in data, "JSON log missing 'version' key"
            assert isinstance(data["timestamp"], (int, float)), "'timestamp' should be a float/int"
            assert isinstance(data["cpu"], int), "'cpu' should be an integer"
            assert 0 <= data["cpu"] <= 100, "'cpu' should be between 0 and 100"
        except json.JSONDecodeError:
            pytest.fail(f"Log line is not valid JSON: {line}")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
