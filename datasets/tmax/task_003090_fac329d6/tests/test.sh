#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import time
import signal
import subprocess
import pytest

DEPLOY_DIR = "/home/user/deploy"
FIFO_PATH = "/home/user/deploy/data.fifo"
DAEMON_EXEC = "/home/user/deploy/daemon_exec"
SUPERVISOR_SCRIPT = "/home/user/deploy/supervisor.sh"
PROCESSED_LOG = "/home/user/deploy/processed.log"
SUPERVISOR_LOG = "/home/user/deploy/supervisor.log"

def get_daemon_pid():
    try:
        pid_str = subprocess.check_output(["pidof", "daemon_exec"]).decode().strip()
        return int(pid_str.split()[0])
    except subprocess.CalledProcessError:
        return None

def write_to_fifo(fifo_writer, data):
    fifo_writer.write(data + "\n")
    fifo_writer.flush()

def test_executables_exist():
    assert os.path.exists(DAEMON_EXEC), f"Executable {DAEMON_EXEC} was not found."
    assert os.access(DAEMON_EXEC, os.X_OK), f"{DAEMON_EXEC} is not executable."

    assert os.path.exists(SUPERVISOR_SCRIPT), f"Supervisor script {SUPERVISOR_SCRIPT} was not found."
    assert os.access(SUPERVISOR_SCRIPT, os.X_OK), f"{SUPERVISOR_SCRIPT} is not executable."

def test_behavior():
    # Clean up logs from any previous manual runs
    if os.path.exists(PROCESSED_LOG):
        os.remove(PROCESSED_LOG)
    if os.path.exists(SUPERVISOR_LOG):
        os.remove(SUPERVISOR_LOG)

    # Start supervisor
    supervisor_proc = subprocess.Popen([SUPERVISOR_SCRIPT], cwd=DEPLOY_DIR)

    # Wait for daemon to start
    time.sleep(1)
    daemon_pid = get_daemon_pid()
    assert daemon_pid is not None, "daemon_exec did not start."

    # Keep one writer open throughout the test so ordinary message boundaries do
    # not generate EOF in the daemon's fgets loop.
    with open(FIFO_PATH, 'w') as fifo_writer:
        # Feed data
        write_to_fifo(fifo_writer, "DATA1")
        write_to_fifo(fifo_writer, "POISON")
        write_to_fifo(fifo_writer, "DATA2")

        time.sleep(1)

        # Check that daemon is still running (didn't crash on POISON)
        current_pid = get_daemon_pid()
        assert current_pid == daemon_pid, "daemon_exec crashed or restarted after receiving POISON."

        # Force kill daemon to test supervisor restart
        os.kill(daemon_pid, signal.SIGKILL)

        # Wait for supervisor to restart it
        time.sleep(2)
        new_pid = get_daemon_pid()
        assert new_pid is not None, "daemon_exec was not restarted by the supervisor."
        assert new_pid != daemon_pid, "daemon_exec PID did not change after kill."

        # Feed more data to the new instance
        write_to_fifo(fifo_writer, "DATA3")

        # Shutdown
        write_to_fifo(fifo_writer, "SHUTDOWN")

        # Wait for supervisor to exit
        try:
            supervisor_proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            supervisor_proc.kill()
            pytest.fail("Supervisor script did not exit after daemon shut down cleanly.")

    assert supervisor_proc.returncode == 0, f"Supervisor script exited with code {supervisor_proc.returncode}, expected 0."

    # Verify processed.log
    assert os.path.exists(PROCESSED_LOG), f"{PROCESSED_LOG} was not created."
    with open(PROCESSED_LOG, 'r') as f:
        processed_content = f.read()

    assert "PROCESSED: DATA1" in processed_content, "DATA1 was not processed."
    assert "PROCESSED: DATA2" in processed_content, "DATA2 was not processed (possibly crashed on POISON)."
    assert "PROCESSED: DATA3" in processed_content, "DATA3 was not processed by the restarted daemon."
    assert "PROCESSED: POISON" not in processed_content, "POISON should be ignored, not processed."

    # Verify supervisor.log
    assert os.path.exists(SUPERVISOR_LOG), f"{SUPERVISOR_LOG} was not created."
    with open(SUPERVISOR_LOG, 'r') as f:
        supervisor_content = f.read()

    warn_msg = "[WARN] Daemon crashed. Restarting..."
    info_msg = "[INFO] Daemon shut down cleanly."

    assert warn_msg in supervisor_content, f"Expected warning message '{warn_msg}' not found in supervisor.log."
    assert supervisor_content.count(warn_msg) == 1, f"Expected exactly 1 warning message in supervisor.log, found {supervisor_content.count(warn_msg)}."
    assert info_msg in supervisor_content, f"Expected info message '{info_msg}' not found in supervisor.log."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
