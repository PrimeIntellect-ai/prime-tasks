#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os


def test_directories_created():
    """Verify that the required directories have been created."""
    directories = [
        "/home/user/config",
        "/home/user/actual_configs",
        "/home/user/run",
        "/home/user/logs"
    ]
    for d in directories:
        assert os.path.isdir(d), f"Directory {d} is missing or not a directory."


def test_config_file_and_content():
    """Verify the config file exists and contains the exact expected lines."""
    config_path = "/home/user/actual_configs/current.conf"
    assert os.path.isfile(config_path), f"Config file {config_path} is missing."

    with open(config_path, "r") as f:
        content = f.read().strip()

    expected_content = "HEARTBEAT_FILE=/home/user/run/hb.txt\nTIMEOUT=2"
    assert content == expected_content, f"Config file content is incorrect. Expected:\n{expected_content}\nGot:\n{content}"


def test_symlink_created_correctly():
    """Verify the symlink exists and points to the correct configuration file."""
    symlink_path = "/home/user/config/service.conf"
    target_path = "/home/user/actual_configs/current.conf"

    assert os.path.islink(symlink_path), f"Symlink {symlink_path} is missing or not a symlink."

    actual_target = os.readlink(symlink_path)
    assert actual_target == target_path, f"Symlink points to {actual_target} instead of {target_path}."


def test_supervisor_files_exist():
    """Verify the supervisor source and executable exist."""
    assert os.path.isfile("/home/user/supervisor.cpp"), "C++ source file /home/user/supervisor.cpp is missing."
    assert os.path.isfile("/home/user/supervisor"), "Executable /home/user/supervisor is missing."
    assert os.access("/home/user/supervisor", os.X_OK), "Executable /home/user/supervisor is not executable."
    with open("/home/user/supervisor", "rb") as f:
        assert f.read(4) == b"\x7fELF", "/home/user/supervisor is not a compiled executable."


def test_heartbeat_exists():
    assert os.path.isfile("/home/user/run/hb.txt"), "Heartbeat file /home/user/run/hb.txt is missing."


def test_alerts_log_content():
    """Verify the alerts.log file exists and contains exactly the expected output."""
    log_path = "/home/user/logs/alerts.log"
    assert os.path.isfile(log_path), f"Log file {log_path} is missing. The supervisor may not have run correctly."

    with open(log_path, "r") as f:
        lines = f.readlines()

    expected_line = "ALERT: Process stalled. Restarting.\n"
    assert len(lines) == 2, f"Expected exactly 2 lines in {log_path}, found {len(lines)}."
    assert lines[0] == expected_line, f"First line of log is incorrect. Got: {lines[0]}"
    assert lines[1] == expected_line, f"Second line of log is incorrect. Got: {lines[1]}"
TEST_EOF

cat << 'BEHAVIOR_EOF' > /tmp/test_behavior.py
import os
import subprocess
import time

CONFIG = "/home/user/actual_configs/current.conf"
LOG = "/home/user/logs/alerts.log"
DEFAULT_HB = "/home/user/run/hb.txt"
TEST_HB = "/home/user/run/verifier-heartbeat.txt"
EXPECTED = b"ALERT: Process stalled. Restarting.\n"
COMPILED = "/tmp/supervisor-from-source"


def read_log():
    try:
        with open(LOG, "rb") as f:
            return f.read()
    except FileNotFoundError:
        return b""


def start_process(path):
    return subprocess.Popen(
        [path],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )


def finish_process(proc, started):
    try:
        stdout, stderr = proc.communicate(timeout=8.0)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.communicate()
        raise AssertionError("Supervisor did not terminate after its five iterations")
    elapsed = time.monotonic() - started
    assert proc.returncode == 0, (
        f"Supervisor exited with status {proc.returncode}; "
        f"stdout={stdout!r}, stderr={stderr!r}"
    )
    assert 4.7 <= elapsed <= 7.5, (
        f"Supervisor runtime was {elapsed:.2f}s, inconsistent with exactly five "
        "iterations beginning with a one-second sleep"
    )


with open(CONFIG, "rb") as f:
    original_config = f.read()
with open(LOG, "rb") as f:
    original_log = f.read()
default_stat = os.stat(DEFAULT_HB)

try:
    subprocess.run(
        ["g++", "-std=c++17", "/home/user/supervisor.cpp", "-o", COMPILED],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )

    # Use a verifier-selected heartbeat and timeout. The stale file must be
    # detected only after the first sleep, then touched so it does not trigger
    # again during this run.
    with open(CONFIG, "w") as f:
        f.write(f"HEARTBEAT_FILE={TEST_HB}\nTIMEOUT=100\n")
    open(TEST_HB, "wb").close()
    stale = time.time() - 1000
    os.utime(TEST_HB, (stale, stale))
    future = time.time() + 1000
    os.utime(DEFAULT_HB, (future, future))
    open(LOG, "wb").close()

    started = time.monotonic()
    proc = start_process("/home/user/supervisor")
    time.sleep(0.55)
    assert proc.poll() is None, "Supervisor exited before completing five sleeps"
    assert read_log() == b"", "Supervisor checked the heartbeat before the first one-second sleep"
    finish_process(proc, started)
    assert read_log() == EXPECTED, "Executable did not emit exactly one derived alert"
    assert os.stat(TEST_HB).st_mtime > stale + 500, "Executable did not touch the stalled heartbeat"

    # Exercise the independently compiled submitted source. Keep the heartbeat
    # fresh through the early iterations, then make it stale shortly before the
    # fifth check; a real five-iteration loop must observe and touch it.
    now = time.time()
    os.utime(TEST_HB, (now, now))
    os.utime(DEFAULT_HB, (future, future))
    open(LOG, "wb").close()

    started = time.monotonic()
    proc = start_process(COMPILED)
    time.sleep(4.15)
    assert proc.poll() is None, "Source-built supervisor ended before its fifth iteration"
    assert read_log() == b"", "Source-built supervisor alerted for a fresh heartbeat"
    stale = time.time() - 1000
    os.utime(TEST_HB, (stale, stale))
    finish_process(proc, started)
    assert read_log() == EXPECTED, "Source-built supervisor did not detect the late stale heartbeat"
    assert os.stat(TEST_HB).st_mtime > stale + 500, "Source-built supervisor did not touch the heartbeat"
finally:
    with open(CONFIG, "wb") as f:
        f.write(original_config)
    with open(LOG, "wb") as f:
        f.write(original_log)
    os.utime(DEFAULT_HB, ns=(default_stat.st_atime_ns, default_stat.st_mtime_ns))
    try:
        os.remove(TEST_HB)
    except FileNotFoundError:
        pass
    try:
        os.remove(COMPILED)
    except FileNotFoundError:
        pass
BEHAVIOR_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1 && python3 /tmp/test_behavior.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
