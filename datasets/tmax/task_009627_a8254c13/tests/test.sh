#!/bin/bash
set -e
mkdir -p /logs/verifier
reward=0
trap 'printf "%s\n" "$reward" > /logs/verifier/reward.txt' EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import io
import json
import os
import signal
import subprocess
import tarfile
import time
import uuid

import pytest

GATHERER = "/home/user/metrics-gatherer.py"
BACKEND = "/home/user/dashboard-backend.py"
ACTIVE_DIR = "/home/user/data/active"
PIDS_PATH = "/home/user/run/pids.json"
ARCHIVE_PATH = "/home/user/backup/metrics_backup.tar.gz"


def service_pids():
    found = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            with open(f"/proc/{entry}/cmdline", "rb") as f:
                cmdline = f.read().replace(b"\0", b" ").decode(errors="replace")
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
        if GATHERER in cmdline or BACKEND in cmdline:
            found.append(int(entry))
    return found


def stop_existing_services():
    pids = service_pids()
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while time.time() < deadline and service_pids():
        time.sleep(0.05)
    for pid in service_pids():
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def process_start_epoch(pid):
    with open(f"/proc/{pid}/stat", "r") as f:
        stat = f.read()
    # Fields after the final ')' begin with field 3; starttime is field 22.
    start_ticks = int(stat.rsplit(")", 1)[1].split()[19])
    ticks_per_second = os.sysconf(os.sysconf_names["SC_CLK_TCK"])
    with open("/proc/uptime", "r") as f:
        uptime = float(f.read().split()[0])
    boot_epoch = time.time() - uptime
    return boot_epoch + (start_ticks / ticks_per_second)


@pytest.fixture(scope="session", autouse=True)
def run_student_script():
    script_path = "/home/user/start_observability.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."

    stop_existing_services()

    os.makedirs(ACTIVE_DIR, exist_ok=True)
    for name in os.listdir(ACTIVE_DIR):
        path = os.path.join(ACTIVE_DIR, name)
        if os.path.isdir(path) and not os.path.islink(path):
            import shutil
            shutil.rmtree(path)
        else:
            os.unlink(path)
    try:
        os.unlink(PIDS_PATH)
    except FileNotFoundError:
        pass

    # Replace the archive with a fresh, unpredictable valid backup. This ensures
    # config.json must be restored from the archive during this invocation.
    expected_config = (json.dumps({
        "metrics_interval": 5,
        "debug": True,
        "verification_nonce": uuid.uuid4().hex,
    }, separators=(",", ":")) + "\n").encode()
    os.makedirs(os.path.dirname(ARCHIVE_PATH), exist_ok=True)
    with tarfile.open(ARCHIVE_PATH, "w:gz") as archive:
        info = tarfile.TarInfo("config.json")
        info.size = len(expected_config)
        info.mode = 0o644
        info.mtime = int(time.time())
        archive.addfile(info, io.BytesIO(expected_config))

    started = time.monotonic()
    try:
        result = subprocess.run(
            [script_path], capture_output=True, text=True, timeout=15
        )
    except subprocess.TimeoutExpired:
        pytest.fail(
            f"Script {script_path} timed out after 15 seconds. "
            "It may not be backgrounding processes correctly."
        )
    elapsed = time.monotonic() - started
    assert result.returncode == 0, (
        f"Script failed with exit code {result.returncode}.\n"
        f"Stdout: {result.stdout}\nStderr: {result.stderr}"
    )

    # Allow a gatherer that was incorrectly bypassed to finish its own delayed
    # startup, so its socket timestamp exposes an early backend launch.
    time.sleep(2.3)

    state = {
        "expected_config": expected_config,
        "elapsed": elapsed,
    }
    yield state
    stop_existing_services()


def test_config_json_extracted(run_student_script):
    config_path = os.path.join(ACTIVE_DIR, "config.json")
    assert os.path.isfile(config_path), (
        f"Expected config file at {config_path} is missing. "
        "Backup was not extracted properly."
    )
    with open(config_path, "rb") as f:
        actual = f.read()
    assert actual == run_student_script["expected_config"], (
        "config.json does not contain the fresh configuration supplied in the "
        "backup archive for this run."
    )


def test_metrics_sock_created():
    sock_path = os.path.join(ACTIVE_DIR, "metrics.sock")
    assert os.path.isfile(sock_path), (
        f"Expected socket file at {sock_path} is missing. "
        "metrics-gatherer.py may not have started successfully or was not waited on."
    )
    with open(sock_path, "r") as f:
        assert f.read() == "mock_socket_active", (
            "metrics.sock was not produced by the running metrics gatherer."
        )


def test_pids_json_exists_and_valid():
    assert os.path.isfile(PIDS_PATH), f"Expected PIDs file at {PIDS_PATH} is missing."
    with open(PIDS_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {PIDS_PATH} does not contain valid JSON.")

    assert "gatherer_pid" in data, "Key 'gatherer_pid' is missing from pids.json."
    assert "backend_pid" in data, "Key 'backend_pid' is missing from pids.json."
    assert isinstance(data["gatherer_pid"], int), "Value for 'gatherer_pid' must be an integer."
    assert isinstance(data["backend_pid"], int), "Value for 'backend_pid' must be an integer."


def test_processes_running():
    if not os.path.isfile(PIDS_PATH):
        pytest.skip("pids.json is missing.")
    with open(PIDS_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.skip("pids.json is invalid.")

    gatherer_pid = data.get("gatherer_pid")
    backend_pid = data.get("backend_pid")
    if not isinstance(gatherer_pid, int) or not isinstance(backend_pid, int):
        pytest.skip("PIDs are not integers.")

    def get_cmdline(pid):
        try:
            with open(f"/proc/{pid}/cmdline", "r") as f:
                return f.read().replace("\x00", " ").strip()
        except FileNotFoundError:
            return None

    gatherer_cmd = get_cmdline(gatherer_pid)
    assert gatherer_cmd is not None, f"Process with PID {gatherer_pid} (gatherer) is not running."
    assert "metrics-gatherer.py" in gatherer_cmd, (
        f"PID {gatherer_pid} does not correspond to metrics-gatherer.py. "
        f"Cmdline: {gatherer_cmd}"
    )

    backend_cmd = get_cmdline(backend_pid)
    assert backend_cmd is not None, f"Process with PID {backend_pid} (backend) is not running."
    assert "dashboard-backend.py" in backend_cmd, (
        f"PID {backend_pid} does not correspond to dashboard-backend.py. "
        f"Cmdline: {backend_cmd}"
    )


def test_gatherer_readiness_precedes_backend(run_student_script):
    with open(PIDS_PATH, "r") as f:
        data = json.load(f)
    gatherer_pid = data["gatherer_pid"]
    backend_pid = data["backend_pid"]
    sock_path = os.path.join(ACTIVE_DIR, "metrics.sock")

    gatherer_started = process_start_epoch(gatherer_pid)
    backend_started = process_start_epoch(backend_pid)
    socket_created = os.stat(sock_path).st_mtime

    # The supplied gatherer creates the readiness file only after its two-second
    # startup delay. The backend must not have been launched before that event.
    assert socket_created - gatherer_started >= 1.5, (
        "metrics.sock existed before the gatherer completed its readiness delay; "
        "the prerequisite appears to have been fabricated."
    )
    assert backend_started + 0.15 >= socket_created, (
        "dashboard-backend.py was launched before metrics-gatherer.py created "
        "its readiness socket."
    )
    assert run_student_script["elapsed"] >= 1.5, (
        "The orchestration script returned too quickly to have waited for the "
        "gatherer's readiness signal."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    reward=1
fi
