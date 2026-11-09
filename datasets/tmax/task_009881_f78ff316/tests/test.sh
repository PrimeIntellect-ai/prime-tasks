#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import signal
import stat
import subprocess
import time
import pytest

SUPERVISOR = "/home/user/supervisor.sh"
BINARY = "/home/user/iot_aggregator/target/release/iot_aggregator"
PID_FILE = "/home/user/run/aggregator.pid"
SENSOR_DIR = "/home/user/sensor_data"
METRICS_DIR = "/home/user/metrics"
CURRENT_JSON = os.path.join(METRICS_DIR, "current.json")
STATE_JSON = os.path.join(METRICS_DIR, "state.json")


def remove_if_present(path):
    try:
        os.remove(path)
    except FileNotFoundError:
        pass


def process_exists(pid):
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


def wait_for_pid(previous=None, timeout=8):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with open(PID_FILE, "r") as f:
                value = f.read().strip()
            if value.isdigit():
                pid = int(value)
                if pid != previous and process_exists(pid):
                    return pid
        except (FileNotFoundError, OSError):
            pass
        time.sleep(0.1)
    return None


def wait_for_json(path, predicate, timeout=8):
    deadline = time.time() + timeout
    last = None
    while time.time() < deadline:
        try:
            with open(path, "r") as f:
                last = json.load(f)
            if predicate(last):
                return last
        except (FileNotFoundError, json.JSONDecodeError, OSError):
            pass
        time.sleep(0.1)
    pytest.fail(f"Timed out waiting for expected JSON in {path}; last value was {last!r}")


def assert_pid_is_aggregator(pid):
    exe = f"/proc/{pid}/exe"
    assert os.path.exists(exe), f"Process {pid} has no executable"
    assert os.path.samefile(exe, BINARY), f"PID {pid} is not the compiled aggregator binary"


def start_supervisor():
    proc = subprocess.Popen([SUPERVISOR], preexec_fn=os.setsid)
    return proc, proc.pid


def stop_supervisor(proc, pgid):
    try:
        os.killpg(pgid, signal.SIGKILL)
    except OSError:
        pass
    try:
        proc.wait(timeout=3)
    except subprocess.TimeoutExpired:
        proc.kill()


def test_deployment_report():
    report_path = "/home/user/deployment_report.txt"
    assert os.path.exists(report_path), f"{report_path} does not exist"

    with open(report_path, "r") as f:
        content = f.read().strip().split('\n')

    expected_lines = [
        "BINARY_PATH=/home/user/iot_aggregator/target/release/iot_aggregator",
        "SUPERVISOR_PATH=/home/user/supervisor.sh",
        "PID_FILE=/home/user/run/aggregator.pid"
    ]

    for expected in expected_lines:
        assert expected in content, f"Expected '{expected}' in deployment_report.txt"


def test_supervisor_executable():
    assert os.path.exists(SUPERVISOR), f"{SUPERVISOR} does not exist"
    assert os.access(SUPERVISOR, os.X_OK), f"{SUPERVISOR} is not executable"


def test_compiled_aggregator_artifact():
    assert os.path.isfile(BINARY), f"{BINARY} does not exist or is not a regular file"
    assert os.access(BINARY, os.X_OK), f"{BINARY} is not executable"
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Release artifact is not a compiled ELF binary"


def test_aggregator_lifecycle():
    log_file = os.path.join(SENSOR_DIR, "log1.log")
    symlink_file = os.path.join(SENSOR_DIR, "latest.log")

    os.makedirs(SENSOR_DIR, exist_ok=True)
    os.makedirs(METRICS_DIR, exist_ok=True)
    os.makedirs(os.path.dirname(PID_FILE), exist_ok=True)
    for path in (PID_FILE, CURRENT_JSON, STATE_JSON, symlink_file, log_file):
        remove_if_present(path)

    supervisor_proc, pgid = start_supervisor()
    try:
        pid = wait_for_pid()
        assert pid is not None, "PID file was not created or does not contain a live PID"
        assert_pid_is_aggregator(pid)

        with open(log_file, "w"):
            pass
        os.symlink(log_file, symlink_file)

        logs = [
            "[2023-10-25T10:00:00Z] sensor=A1 temp=20.5C humidity=40% status=OK\n",
            "[2023-10-25T10:00:01Z] sensor=A1 temp=99.9C humidity=99% status=ERROR\n",
            "[2023-10-25T10:00:02Z] sensor=A1 temp=21.0C humidity=42% status=OK\n"
        ]
        with open(log_file, "a") as f:
            for line in logs:
                f.write(line)
                f.flush()
                time.sleep(0.5)

        data = wait_for_json(
            CURRENT_JSON,
            lambda d: d.get("latest_temp") == 21.0
            and d.get("latest_humidity") == 42.0
            and d.get("valid_readings_count") == 2,
        )
        assert data.get("latest_temp") == 21.0, f"Expected latest_temp=21.0, got {data.get('latest_temp')}"
        assert data.get("latest_humidity") == 42.0, f"Expected latest_humidity=42.0, got {data.get('latest_humidity')}"
        assert data.get("valid_readings_count") == 2, f"Expected valid_readings_count=2, got {data.get('valid_readings_count')}"

        os.kill(pid, signal.SIGTERM)
        state_data = wait_for_json(STATE_JSON, lambda d: d.get("status") == "shutting_down")
        assert state_data.get("status") == "shutting_down", f"Expected status='shutting_down', got {state_data.get('status')}"

        deadline = time.time() + 3
        while time.time() < deadline and process_exists(pid):
            time.sleep(0.1)
        if process_exists(pid):
            pytest.fail(f"Process {pid} did not exit after SIGTERM")
    finally:
        stop_supervisor(supervisor_proc, pgid)


def test_dynamic_parsing_and_unexpected_exit_restart():
    rng = secrets.SystemRandom()
    log_file = os.path.join(SENSOR_DIR, f"dynamic-{secrets.token_hex(6)}.log")
    symlink_file = os.path.join(SENSOR_DIR, "latest.log")

    os.makedirs(SENSOR_DIR, exist_ok=True)
    os.makedirs(METRICS_DIR, exist_ok=True)
    os.makedirs(os.path.dirname(PID_FILE), exist_ok=True)
    for path in (PID_FILE, CURRENT_JSON, STATE_JSON, symlink_file):
        remove_if_present(path)
    with open(log_file, "w"):
        pass
    os.symlink(log_file, symlink_file)

    first_temp = round(rng.uniform(10.0, 35.0), 1)
    first_humidity = float(rng.randint(15, 45))
    latest_temp = round(rng.uniform(55.0, 85.0), 1)
    latest_humidity = float(rng.randint(55, 90))
    error_temp = round(rng.uniform(90.0, 99.0), 1)
    offline_temp = round(rng.uniform(1.0, 9.0), 1)

    supervisor_proc, pgid = start_supervisor()
    try:
        pid = wait_for_pid()
        assert pid is not None, "Supervisor did not create a live aggregator PID"
        assert_pid_is_aggregator(pid)

        dynamic_logs = [
            f"[2026-01-02T03:04:05Z] sensor=R{rng.randint(100,999)} temp={first_temp:.1f}C humidity={first_humidity:.0f}% status=OK\n",
            f"[2026-01-02T03:04:06Z] sensor=R{rng.randint(100,999)} temp={error_temp:.1f}C humidity=98% status=ERROR\n",
            f"[2026-01-02T03:04:07Z] sensor=R{rng.randint(100,999)} temp={offline_temp:.1f}C humidity=2% status=OFFLINE\n",
            f"[2026-01-02T03:04:08Z] sensor=R{rng.randint(100,999)} temp={latest_temp:.1f}C humidity={latest_humidity:.0f}% status=OK\n",
        ]
        with open(log_file, "a") as f:
            for line in dynamic_logs:
                f.write(line)
                f.flush()
                time.sleep(0.15)

        data = wait_for_json(
            CURRENT_JSON,
            lambda d: d.get("latest_temp") == latest_temp
            and d.get("latest_humidity") == latest_humidity
            and d.get("valid_readings_count") == 2,
        )
        assert set(data.keys()) == {"latest_temp", "latest_humidity", "valid_readings_count"}

        os.kill(pid, signal.SIGKILL)
        restarted_pid = wait_for_pid(previous=pid, timeout=8)
        assert restarted_pid is not None, "Supervisor did not restart the aggregator after an unexpected exit"
        assert restarted_pid != pid, "PID file was not updated after restart"
        assert supervisor_proc.poll() is None, "Supervisor exited instead of monitoring and restarting"
        assert_pid_is_aggregator(restarted_pid)

        remove_if_present(CURRENT_JSON)
        restart_temp = round(rng.uniform(36.0, 54.0), 1)
        restart_humidity = float(rng.randint(20, 80))
        with open(log_file, "a") as f:
            f.write(f"[2026-01-02T03:04:09Z] sensor=AFTER_RESTART temp={restart_temp:.1f}C humidity={restart_humidity:.0f}% status=OK\n")
            f.flush()

        restarted_data = wait_for_json(
            CURRENT_JSON,
            lambda d: d.get("latest_temp") == restart_temp
            and d.get("latest_humidity") == restart_humidity
            and isinstance(d.get("valid_readings_count"), int)
            and d.get("valid_readings_count") >= 1,
        )
        assert set(restarted_data.keys()) == {"latest_temp", "latest_humidity", "valid_readings_count"}
    finally:
        stop_supervisor(supervisor_proc, pgid)
        remove_if_present(log_file)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
