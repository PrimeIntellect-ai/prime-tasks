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

APP = "/home/user/app"
DATA = "/home/user/data"
LAUNCHER = f"{APP}/start_worker.sh"
HEALTH_CHECK = f"{APP}/health_check.py"
PID_FILE = f"{APP}/worker.pid"
LOG_FILE = f"{DATA}/worker.log"
HEALTH_JSON = f"{APP}/health.json"
WORKER = f"{APP}/worker.py"


def read_cmdline(pid):
    with open(f"/proc/{pid}/cmdline", "rb") as f:
        return [part.decode(errors="replace") for part in f.read().split(b"\0") if part]


def worker_pids():
    result = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            cmd = read_cmdline(int(entry))
            if len(cmd) >= 2 and os.path.basename(cmd[0]).startswith("python") and cmd[1] == WORKER:
                result.append(int(entry))
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return result


def terminate_existing_workers():
    pids = worker_pids()
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
    while time.time() < deadline and any(os.path.exists(f"/proc/{pid}") for pid in pids):
        time.sleep(0.05)
    for pid in pids:
        if os.path.exists(f"/proc/{pid}"):
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass


def wait_for_file(path, timeout=8):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if os.path.isfile(path):
            return
        time.sleep(0.1)
    assert False, f"Timed out waiting for {path}."


def run_health():
    if os.path.exists(HEALTH_JSON):
        os.unlink(HEALTH_JSON)
    completed = subprocess.run(
        ["python3", HEALTH_CHECK],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert completed.returncode == 0, f"Health check crashed: {completed.stderr}"
    assert os.path.isfile(HEALTH_JSON), "Health check did not generate health.json."
    with open(HEALTH_JSON) as f:
        data = json.load(f)
    assert set(data) == {"status", "pid"}, "health.json must contain exactly status and pid."
    return data


def write_pid(value):
    with open(PID_FILE, "w") as f:
        f.write(value)


def test_00_scripts_behave_correctly():
    assert os.path.isfile(LAUNCHER), f"Script {LAUNCHER} is missing."
    mode = os.stat(LAUNCHER).st_mode
    assert mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH), f"Script {LAUNCHER} is not executable."
    assert os.path.isfile(HEALTH_CHECK), f"Health check script {HEALTH_CHECK} is missing."

    terminate_existing_workers()
    for path in (PID_FILE, LOG_FILE, HEALTH_JSON):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass

    launch_time = time.time()
    completed = subprocess.run(
        [LAUNCHER],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert completed.returncode == 0, f"Launch script failed: {completed.stderr}"
    wait_for_file(PID_FILE)
    assert os.path.getmtime(PID_FILE) >= launch_time - 1, "Launch script did not freshly create worker.pid."

    content = open(PID_FILE).read().strip()
    assert content.isdigit(), "Launch script did not save a valid PID."
    pid = int(content)
    wait_for_file(f"/proc/{pid}/cmdline")

    cmd = read_cmdline(pid)
    assert len(cmd) >= 2, f"PID {pid} has an unexpected command line: {cmd}"
    assert os.path.basename(cmd[0]).startswith("python"), f"PID {pid} is not a Python worker process: {cmd}"
    assert cmd[1] == WORKER, f"PID {pid} does not belong to {WORKER}: {cmd}"
    with open(f"/proc/{pid}/status") as f:
        status_text = f.read()
    assert "State:\tZ" not in status_text, f"Worker PID {pid} is a zombie."
    with open(f"/proc/{pid}/environ", "rb") as f:
        environment = f.read().split(b"\0")
    assert b"DATA_DIR=/home/user/data" in environment, "Worker was not launched with the required DATA_DIR."

    wait_for_file(LOG_FILE)
    deadline = time.time() + 8
    while time.time() < deadline and os.path.getsize(LOG_FILE) == 0:
        time.sleep(0.1)
    assert os.path.getsize(LOG_FILE) > 0, "The launched worker did not write to worker.log."
    assert os.path.getmtime(LOG_FILE) >= launch_time - 1, "worker.log was not freshly written by the launch."
    with open(LOG_FILE, errors="replace") as f:
        assert "Worker heartbeat" in f.read(), "worker.log does not contain a worker heartbeat."

    os.kill(pid, signal.SIGSTOP)
    try:
        os.unlink(PID_FILE)
        data = run_health()
        assert data == {"status": "unhealthy", "pid": None}, "Missing PID file must produce unhealthy with null pid."

        write_pid("not-a-pid\n")
        data = run_health()
        assert data == {"status": "unhealthy", "pid": None}, "Invalid PID file must produce unhealthy with null pid."

        dead_pid = 4194303
        assert not os.path.exists(f"/proc/{dead_pid}"), "Chosen dead PID unexpectedly exists."
        write_pid(f"{dead_pid}\n")
        data = run_health()
        assert data == {"status": "unhealthy", "pid": dead_pid}, "A dead numeric PID must be reported as unhealthy."

        write_pid(f"{pid}\n")
        os.unlink(LOG_FILE)
        data = run_health()
        assert data == {"status": "unhealthy", "pid": pid}, "A missing worker log must produce unhealthy."

        with open(LOG_FILE, "w") as f:
            f.write("stale heartbeat\n")
        stale_time = time.time() - 120
        os.utime(LOG_FILE, (stale_time, stale_time))
        data = run_health()
        assert data == {"status": "unhealthy", "pid": pid}, "A stale worker log must produce unhealthy."
    finally:
        try:
            os.kill(pid, signal.SIGCONT)
        except ProcessLookupError:
            pass

    assert os.path.isdir(f"/proc/{pid}"), "Worker stopped during health-check testing."
    write_pid(f"{pid}\n")
    with open(LOG_FILE, "a") as f:
        f.write("fresh verifier heartbeat\n")
    os.utime(LOG_FILE, None)
    data = run_health()
    assert data == {"status": "healthy", "pid": pid}, "Running worker with a fresh log must produce healthy."


def test_start_worker_script():
    script_path = "/home/user/app/start_worker.sh"
    assert os.path.isfile(script_path), f"Script {script_path} is missing."

    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR) or bool(st.st_mode & stat.S_IXGRP) or bool(st.st_mode & stat.S_IXOTH), \
        f"Script {script_path} is not executable."


def test_worker_pid_and_process():
    pid_file = "/home/user/app/worker.pid"
    assert os.path.isfile(pid_file), f"PID file {pid_file} is missing."

    with open(pid_file, "r") as f:
        content = f.read().strip()

    assert content.isdigit(), f"PID file {pid_file} does not contain a valid integer PID."
    pid = int(content)

    proc_dir = f"/proc/{pid}"
    assert os.path.isdir(proc_dir), f"Process with PID {pid} is not running."


def test_worker_log_exists():
    log_file = "/home/user/data/worker.log"
    assert os.path.isfile(log_file), f"Worker log {log_file} is missing. The worker might not be writing to the correct DATA_DIR."
    assert time.time() - os.path.getmtime(log_file) < 60, f"Worker log {log_file} is stale."


def test_health_check_script_exists():
    script_path = "/home/user/app/health_check.py"
    assert os.path.isfile(script_path), f"Health check script {script_path} is missing."


def test_health_json_content():
    json_file = "/home/user/app/health.json"
    assert os.path.isfile(json_file), f"Health JSON file {json_file} is missing."

    with open(json_file, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"File {json_file} does not contain valid JSON."

    assert "status" in data, f"Key 'status' is missing from {json_file}."
    assert data["status"] == "healthy", f"Expected status 'healthy', got '{data['status']}'."

    pid_file = "/home/user/app/worker.pid"
    if os.path.isfile(pid_file):
        with open(pid_file, "r") as f:
            content = f.read().strip()
            if content.isdigit():
                expected_pid = int(content)
                assert "pid" in data, f"Key 'pid' is missing from {json_file}."
                assert data["pid"] == expected_pid, f"Expected pid {expected_pid}, got {data['pid']}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
