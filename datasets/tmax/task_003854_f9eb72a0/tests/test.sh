#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
import time

MANAGER = "/home/user/manager.sh"
HEALTH = "/home/user/health_check.sh"
CONF = "/home/user/staging/etc/app.conf"
PID_FILE = "/home/user/staging/app.pid"
REPORT = "/home/user/restore_report.log"
APP = "/home/user/staging/bin/app_mock"


def read_pid():
    assert os.path.isfile(PID_FILE), f"PID file {PID_FILE} is missing."
    with open(PID_FILE, "r") as f:
        pid_str = f.read().strip()
    assert pid_str.isdigit(), f"PID file {PID_FILE} does not contain a valid numeric PID."
    return int(pid_str)


def process_is_live(pid):
    try:
        with open(f"/proc/{pid}/stat", "r") as f:
            state = f.read().split()[2]
        return state != "Z"
    except (FileNotFoundError, ProcessLookupError, IndexError):
        return False


def wait_for_live(pid, expected, timeout=5):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if process_is_live(pid) == expected:
            return True
        time.sleep(0.1)
    return process_is_live(pid) == expected


def run_health():
    return subprocess.run([HEALTH], capture_output=True, text=True, timeout=10)


def report_lines():
    assert os.path.isfile(REPORT), f"Report log {REPORT} is missing."
    with open(REPORT, "r") as f:
        return [line.strip() for line in f.readlines() if line.strip()]


def test_staging_directory_extracted():
    """Test that the archive was extracted to the staging directory."""
    assert os.path.isfile(APP), f"Extracted file {APP} is missing."
    assert os.access(APP, os.X_OK), f"{APP} should be executable."


def test_app_conf_modified():
    """Test that etc/app.conf was modified correctly."""
    assert os.path.isfile(CONF), f"Configuration file {CONF} is missing."
    with open(CONF, "r") as f:
        content = f.read()
    assert "listen_port=8080" in content, "listen_port was not updated to 8080 in app.conf."
    assert "db_path=/home/user/staging/data/db.sqlite" in content, "db_path was not updated correctly in app.conf."


def test_manager_script_exists_and_executable():
    """Test that manager.sh exists and is executable."""
    assert os.path.isfile(MANAGER), f"Manager script {MANAGER} is missing."
    assert os.access(MANAGER, os.X_OK), f"Manager script {MANAGER} is not executable."


def test_app_running():
    """Test that the app is running and the PID file exists."""
    pid = read_pid()
    try:
        os.kill(pid, 0)
    except OSError:
        assert False, f"Process with PID {pid} from {PID_FILE} is not running."
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            cmdline = f.read().replace(b"\x00", b" ").decode(errors="replace")
        assert "app_mock" in cmdline, f"Process {pid} is not running app_mock. Cmdline: {cmdline}"
    except FileNotFoundError:
        assert False, f"/proc/{pid}/cmdline not found, process might have died."


def test_manager_status_command():
    """Test that manager.sh status exits with 0 when the app is running."""
    result = subprocess.run([MANAGER, "status"], capture_output=True, timeout=5)
    assert result.returncode == 0, f"manager.sh status exited with {result.returncode}, expected 0."


def test_manager_stop_and_start_commands():
    """Exercise the required lifecycle rather than trusting the initial process."""
    old_pid = read_pid()
    stopped = subprocess.run([MANAGER, "stop"], capture_output=True, text=True, timeout=10)
    assert stopped.returncode == 0, f"manager.sh stop failed: {stopped.stdout} {stopped.stderr}"
    assert not os.path.exists(PID_FILE), "manager.sh stop did not remove app.pid."
    assert wait_for_live(old_pid, False), f"manager.sh stop did not terminate process {old_pid}."

    status = subprocess.run([MANAGER, "status"], capture_output=True, timeout=5)
    assert status.returncode == 1, f"manager.sh status returned {status.returncode} after stop, expected 1."

    started = subprocess.run([MANAGER, "start"], capture_output=True, text=True, timeout=10)
    assert started.returncode == 0, f"manager.sh start failed: {started.stdout} {started.stderr}"
    new_pid = read_pid()
    assert wait_for_live(new_pid, True), f"Process {new_pid} started by manager.sh is not running."

    with open(f"/proc/{new_pid}/cmdline", "rb") as f:
        argv = [part.decode(errors="replace") for part in f.read().split(b"\x00") if part]
    assert APP in argv, f"manager.sh did not execute {APP}; argv was {argv}."
    app_index = argv.index(APP)
    assert argv[app_index + 1:] == [CONF], f"app_mock must receive only {CONF}; argv was {argv}."

    status = subprocess.run([MANAGER, "status"], capture_output=True, timeout=5)
    assert status.returncode == 0, "manager.sh status did not recognize the process started by manager.sh."


def test_health_check_exists_and_handles_failed_status():
    """Ensure the monitoring artifact exists, runs, and reports an invalid stopped restore."""
    assert os.path.isfile(HEALTH), f"Health check script {HEALTH} is missing."
    assert os.access(HEALTH, os.X_OK), f"Health check script {HEALTH} is not executable."

    stopped = subprocess.run([MANAGER, "stop"], capture_output=True, text=True, timeout=10)
    assert stopped.returncode == 0, f"manager.sh stop failed before health check: {stopped.stderr}"
    try:
        run_health()
        lines = report_lines()
        assert "[PORT] 8080" in lines, "Health check did not read listen_port from app.conf."
        assert "[DB] /home/user/staging/data/db.sqlite" in lines, "Health check did not read db_path from app.conf."
        assert "[RESULT] RESTORE INVALID" in lines, "Health check did not mark a stopped service invalid."
    finally:
        started = subprocess.run([MANAGER, "start"], capture_output=True, text=True, timeout=10)
        assert started.returncode == 0, f"Could not restart service after failed-status health check: {started.stderr}"
        pid = read_pid()
        assert wait_for_live(pid, True), "Restarted application is not running."


def test_health_check_derives_report_from_configuration():
    """Change configuration to unpredictable values and require health_check.sh to read them."""
    with open(CONF, "r") as f:
        original = f.read()

    port = str(20000 + secrets.randbelow(30000))
    db_path = f"/home/user/staging/data/check-{secrets.token_hex(8)}.sqlite"
    changed = re.sub(r"(?m)^listen_port=.*$", f"listen_port={port}", original)
    changed = re.sub(r"(?m)^db_path=.*$", f"db_path={db_path}", changed)
    assert changed != original

    try:
        with open(CONF, "w") as f:
            f.write(changed)
        run_health()
        assert report_lines() == [
            "[STATUS] RUNNING",
            f"[PORT] {port}",
            f"[DB] {db_path}",
            "[RESULT] RESTORE VALID",
        ], "health_check.sh did not generate the exact report from the current configuration."
    finally:
        with open(CONF, "w") as f:
            f.write(original)
        run_health()


def test_restore_report_log():
    """Test that the restore report log matches the expected format and content."""
    assert os.path.isfile(REPORT), f"Report log {REPORT} is missing."
    expected_lines = [
        "[STATUS] RUNNING",
        "[PORT] 8080",
        "[DB] /home/user/staging/data/db.sqlite",
        "[RESULT] RESTORE VALID"
    ]
    with open(REPORT, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]
    for expected in expected_lines:
        assert expected in lines, f"Expected line '{expected}' not found in {REPORT}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
