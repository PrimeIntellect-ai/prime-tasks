#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'BEHAVIOR_EOF' > /tmp/test_behavior.py
import os
import shutil
import stat
import subprocess
import sys
import time

ROGUE = "/home/user/rogue_service.py"
MONITOR = "/home/user/storage_monitor.py"
LOG_DIR = "/home/user/app_data/logs_v1"
SYMLINK = "/home/user/app_data/current_logs"
ALERT = "/home/user/alerts.log"

EXPECTED_ROGUE = '''import time
import os

log_dir = "/home/user/app_data/current_logs"
os.makedirs(log_dir, exist_ok=True)
chunk = b"A" * 1024 * 1024  # 1 MB chunk

try:
    while True:
        with open(os.path.join(log_dir, f"spam_{time.time()}.log"), "wb") as f:
            f.write(chunk)
        time.sleep(1)
except KeyboardInterrupt:
    pass
'''

def assert_regular_file(path):
    assert os.path.exists(path), f"{path} does not exist"
    assert not os.path.islink(path), f"{path} must be a regular file, not a symlink"
    assert stat.S_ISREG(os.stat(path).st_mode), f"{path} is not a regular file"

def no_matching_process(pattern):
    result = subprocess.run(["pgrep", "-f", pattern], stdout=subprocess.PIPE, text=True)
    assert result.returncode == 1, f"A pre-existing {pattern} process is running: {result.stdout.strip()}"

assert os.path.isdir(LOG_DIR), f"Directory {LOG_DIR} does not exist"
assert os.path.islink(SYMLINK), f"{SYMLINK} is not a symbolic link"
assert os.readlink(SYMLINK).rstrip('/') == LOG_DIR
assert_regular_file(ROGUE)
assert_regular_file(MONITOR)

with open(ROGUE, "r") as f:
    actual_rogue = f.read()
assert actual_rogue == EXPECTED_ROGUE, "rogue_service.py does not contain the exact required code"

# Ensure the submitted monitor is at least valid Python before executing it.
subprocess.run([sys.executable, "-m", "py_compile", MONITOR], check=True)
no_matching_process("rogue_service.py")
no_matching_process("storage_monitor.py")

# Create a clean trial so a fabricated pre-existing alert or dummy quota files cannot pass.
for entry in os.scandir(LOG_DIR):
    if entry.is_dir(follow_symlinks=False):
        shutil.rmtree(entry.path)
    else:
        os.unlink(entry.path)
if os.path.lexists(ALERT):
    os.unlink(ALERT)

rogue = None
monitor = None
try:
    rogue = subprocess.Popen(
        [sys.executable, ROGUE],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    time.sleep(0.2)
    assert rogue.poll() is None, "rogue_service.py did not remain running"
    rogue_pid = rogue.pid

    monitor = subprocess.Popen(
        [sys.executable, MONITOR],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    try:
        monitor_status = monitor.wait(timeout=12)
    except subprocess.TimeoutExpired:
        raise AssertionError("storage_monitor.py did not detect the quota violation and exit in time")

    assert monitor_status == 0, f"storage_monitor.py exited with status {monitor_status}, expected 0"
    try:
        rogue.wait(timeout=3)
    except subprocess.TimeoutExpired:
        raise AssertionError("storage_monitor.py exited without terminating rogue_service.py")

    total_size = sum(
        os.path.getsize(os.path.join(LOG_DIR, name))
        for name in os.listdir(LOG_DIR)
        if os.path.isfile(os.path.join(LOG_DIR, name))
    )
    assert total_size > 5 * 1024 * 1024, \
        f"Monitor acted before the quota was strictly exceeded ({total_size} bytes)"

    assert os.path.isfile(ALERT), f"Alert log {ALERT} was not created"
    with open(ALERT, "r") as f:
        alert = f.read().strip()
    expected_alert = f"ALERT: Quota exceeded. Rogue PID {rogue_pid} killed."
    assert alert == expected_alert, \
        f"Alert was {alert!r}; expected the actual rogue PID in {expected_alert!r}"
finally:
    for process in (monitor, rogue):
        if process is not None and process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=2)
BEHAVIOR_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import re
import subprocess

def test_directory_and_symlink():
    log_dir = "/home/user/app_data/logs_v1"
    symlink = "/home/user/app_data/current_logs"

    assert os.path.isdir(log_dir), f"Directory {log_dir} does not exist."
    assert os.path.islink(symlink), f"{symlink} is not a symbolic link."

    target = os.readlink(symlink)
    # Both /home/user/app_data/logs_v1 and /home/user/app_data/logs_v1/ are acceptable
    assert target.rstrip('/') == log_dir, f"Symlink {symlink} points to {target}, expected {log_dir}"

def test_log_directory_size():
    log_dir = "/home/user/app_data/logs_v1"
    assert os.path.isdir(log_dir), f"Directory {log_dir} does not exist."

    total_size = sum(
        os.path.getsize(os.path.join(log_dir, f))
        for f in os.listdir(log_dir)
        if os.path.isfile(os.path.join(log_dir, f))
    )

    assert total_size > 5 * 1024 * 1024, f"Total log size is {total_size} bytes, which is not strictly greater than 5MB."

def test_alert_log_content():
    alert_log = "/home/user/alerts.log"
    assert os.path.isfile(alert_log), f"Alert log {alert_log} does not exist."

    with open(alert_log, "r") as f:
        content = f.read().strip()

    pattern = r"^ALERT: Quota exceeded\. Rogue PID \d+ killed\.$"
    assert re.match(pattern, content), f"Alert log content '{content}' does not match expected format."

def test_processes_terminated():
    # Check if rogue_service.py is running
    try:
        output = subprocess.check_output(["pgrep", "-f", "rogue_service.py"]).decode()
        pids = output.strip().split()
        assert not pids, f"rogue_service.py is still running with PIDs: {pids}"
    except subprocess.CalledProcessError:
        # pgrep returns 1 if no processes found, which is expected
        pass

    # Check if storage_monitor.py is running
    try:
        output = subprocess.check_output(["pgrep", "-f", "storage_monitor.py"]).decode()
        pids = output.strip().split()
        assert not pids, f"storage_monitor.py is still running with PIDs: {pids}"
    except subprocess.CalledProcessError:
        pass
TEST_EOF

if python3 /tmp/test_behavior.py 2>&1 && python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
