#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import datetime
import os
import re
import stat
import subprocess
import time

SCRIPT_PATH = "/home/user/ensure_service.sh"
MICROSERVICE_PATH = "/home/user/microservice.sh"
PID_FILE = "/home/user/service.pid"
LOG_FILE = "/home/user/watcher.log"
EXACT_LOG_RE = re.compile(r"^\[([0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2})\] Action: (STARTED|RUNNING|RESTARTED)$")

def kill_microservice():
    """Helper to kill any running microservice processes."""
    try:
        subprocess.run(["pkill", "-f", "microservice.sh"], check=False)
    except Exception:
        pass

def is_process_running(pid):
    """Check if a process with the given PID is running."""
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False

def assert_is_microservice(pid):
    """Confirm that PID is the requested microservice, not an arbitrary process."""
    cmdline_path = f"/proc/{pid}/cmdline"
    assert os.path.exists(cmdline_path), f"Process {pid} has no proc entry."
    with open(cmdline_path, "rb") as f:
        argv = [arg.decode(errors="replace") for arg in f.read().split(b"\0") if arg]
    assert MICROSERVICE_PATH in argv, (
        f"PID {pid} is not {MICROSERVICE_PATH}; command line was {argv!r}."
    )

def read_log_lines():
    if not os.path.exists(LOG_FILE):
        return []
    with open(LOG_FILE, "r") as f:
        return f.read().splitlines()

def get_last_log_line():
    """Get the last line of the watcher log."""
    lines = read_log_lines()
    return lines[-1].strip() if lines else ""

def run_and_check_single_log(expected_action):
    before = read_log_lines()
    started_at = time.time()
    subprocess.run([SCRIPT_PATH], check=True)
    finished_at = time.time()
    time.sleep(1)
    after = read_log_lines()

    assert len(after) == len(before) + 1, (
        f"Each execution must append exactly one log line; had {len(before)} lines before "
        f"and {len(after)} after."
    )
    line = after[-1]
    match = EXACT_LOG_RE.fullmatch(line)
    assert match, f"Log line does not have the required exact format: {line!r}"
    assert match.group(2) == expected_action, (
        f"Expected action {expected_action}, got {match.group(2)}."
    )
    timestamp = datetime.datetime.strptime(match.group(1), "%Y-%m-%d %H:%M:%S").timestamp()
    assert started_at - 2 <= timestamp <= finished_at + 2, (
        f"Log timestamp was not generated for this execution: {line!r}"
    )

def test_script_exists_and_executable():
    """Test that ensure_service.sh exists and is executable."""
    assert os.path.exists(SCRIPT_PATH), f"Expected script {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"Expected {SCRIPT_PATH} to be a file."
    st = os.stat(SCRIPT_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), f"Expected {SCRIPT_PATH} to be executable."

def test_crontab_scheduled():
    """Test that the script is scheduled in crontab to run every minute."""
    result = subprocess.run(["crontab", "-l"], capture_output=True, text=True)
    assert result.returncode == 0, "Failed to read crontab."

    found = False
    for line in result.stdout.splitlines():
        if line.strip().startswith("#"):
            continue
        if "ensure_service.sh" in line:
            parts = line.split()
            if len(parts) >= 5 and parts[:5] == ["*", "*", "*", "*", "*"]:
                found = True
                break

    assert found, "ensure_service.sh is not scheduled to run every minute (* * * * *) in crontab."

def test_script_behavior_started():
    """Test the STARTED state of the script."""
    kill_microservice()
    if os.path.exists(PID_FILE):
        os.remove(PID_FILE)

    run_and_check_single_log("STARTED")

    last_log = get_last_log_line()
    assert re.search(r"Action:\s*STARTED$", last_log), f"Log did not indicate STARTED. Last line: {last_log}"

    assert os.path.exists(PID_FILE), "PID file was not created."
    with open(PID_FILE, "r") as f:
        pid = int(f.read().strip())
    assert is_process_running(pid), "Microservice process is not running after STARTED action."
    assert_is_microservice(pid)

def test_script_behavior_running():
    """Test the RUNNING state of the script."""
    if not os.path.exists(PID_FILE):
        subprocess.run([SCRIPT_PATH], check=True)
        time.sleep(1)

    with open(PID_FILE, "r") as f:
        old_pid = int(f.read().strip())
    assert_is_microservice(old_pid)

    run_and_check_single_log("RUNNING")

    last_log = get_last_log_line()
    assert re.search(r"Action:\s*RUNNING$", last_log), f"Log did not indicate RUNNING. Last line: {last_log}"
    with open(PID_FILE, "r") as f:
        current_pid = int(f.read().strip())
    assert current_pid == old_pid, "RUNNING action replaced the existing service process."
    assert is_process_running(current_pid), "Microservice process is not running after RUNNING action."
    assert_is_microservice(current_pid)

def test_script_behavior_restarted():
    """Test the RESTARTED state of the script."""
    if not os.path.exists(PID_FILE):
        subprocess.run([SCRIPT_PATH], check=True)
        time.sleep(1)

    with open(PID_FILE, "r") as f:
        old_pid = int(f.read().strip())
    assert_is_microservice(old_pid)

    try:
        os.kill(old_pid, 9)
    except OSError:
        pass
    time.sleep(1)

    assert not is_process_running(old_pid), "Failed to kill the old process for testing."
    assert os.path.exists(PID_FILE), "PID file should still exist for this test."

    run_and_check_single_log("RESTARTED")

    last_log = get_last_log_line()
    assert re.search(r"Action:\s*RESTARTED$", last_log), f"Log did not indicate RESTARTED. Last line: {last_log}"

    assert os.path.exists(PID_FILE), "PID file was not created after restart."
    with open(PID_FILE, "r") as f:
        new_pid = int(f.read().strip())
    assert is_process_running(new_pid), "Microservice process is not running after RESTARTED action."
    assert old_pid != new_pid, "Process ID did not change after restart."
    assert_is_microservice(new_pid)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
