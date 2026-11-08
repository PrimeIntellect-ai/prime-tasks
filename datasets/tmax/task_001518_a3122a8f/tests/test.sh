#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import signal
import socket
import subprocess
import time

import pytest

HEALTHD = "/home/user/healthd"
SOURCE = "/home/user/healthd.c"
PID_FILE = "/home/user/worker.pid"
LOG_FILE = "/home/user/logs/status.log"


def read_response():
    try:
        with socket.create_connection(("127.0.0.1", 8080), timeout=2) as sock:
            sock.settimeout(2)
            chunks = []
            while True:
                data = sock.recv(1024)
                if not data:
                    break
                chunks.append(data)
                if sum(map(len, chunks)) > 4096:
                    pytest.fail("Daemon returned an unexpectedly large response")
            return b"".join(chunks)
    except ConnectionRefusedError:
        pytest.fail("Daemon is not listening on 127.0.0.1:8080")
    except socket.timeout:
        pytest.fail("Daemon did not send its response and immediately close the connection")
    except Exception as exc:
        pytest.fail(f"Failed to connect or read from daemon: {exc}")


def listener_inodes():
    found = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as handle:
                next(handle, None)
                for line in handle:
                    fields = line.split()
                    if len(fields) < 10:
                        continue
                    local = fields[1]
                    state = fields[3]
                    if state == "0A" and int(local.rsplit(":", 1)[1], 16) == 8080:
                        found.add(fields[9])
        except FileNotFoundError:
            pass
    return found


def listener_pids():
    inodes = listener_inodes()
    owners = set()
    if not inodes:
        return owners
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                match = re.fullmatch(r"socket:\[(\d+)\]", target)
                if match and match.group(1) in inodes:
                    owners.add(int(name))
                    break
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
    return owners


def stop_existing_listener():
    owners = listener_pids()
    assert 1 not in owners, "Refusing to replace a port-8080 listener owned by PID 1"
    for pid in owners:
        os.kill(pid, signal.SIGTERM)
    deadline = time.time() + 2
    while listener_inodes() and time.time() < deadline:
        time.sleep(0.05)
    for pid in listener_pids():
        if pid != 1:
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
    deadline = time.time() + 2
    while listener_inodes() and time.time() < deadline:
        time.sleep(0.05)
    assert not listener_inodes(), "Could not stop the previous port-8080 listener"


def test_complete_setup_and_behavior():
    # Preserve the original artifact assertions and require the requested source.
    assert os.path.isfile(HEALTHD), f"Executable {HEALTHD} not found."
    assert os.access(HEALTHD, os.X_OK), f"File {HEALTHD} is not executable."
    assert os.path.isfile(SOURCE), f"C source {SOURCE} not found."
    with open(HEALTHD, "rb") as handle:
        assert handle.read(4) == b"\x7fELF", f"{HEALTHD} is not a compiled ELF executable"

    assert os.path.isfile(PID_FILE), f"PID file {PID_FILE} not found."
    with open(PID_FILE) as handle:
        original_pid_text = handle.read().strip()
    assert original_pid_text.isdigit(), f"PID file does not contain a valid integer: '{original_pid_text}'"
    worker_pid = int(original_pid_text)
    assert os.path.isdir(f"/proc/{worker_pid}"), f"Worker process with PID {worker_pid} is not running."

    # Preserve the original healthy-state check against the daemon left running by the agent.
    initial_response = read_response().decode("utf-8", errors="replace").strip()
    assert "STATUS: OK" in initial_response, f"Expected 'STATUS: OK' in response, got '{initial_response}'"

    result = subprocess.run(["crontab", "-l"], capture_output=True, text=True)
    assert result.returncode == 0, "Failed to read crontab."
    crontab_content = result.stdout
    assert "LOG_DIR=/home/user/logs" in crontab_content, "Crontab does not contain 'LOG_DIR=/home/user/logs'"
    assert "/home/user/query_health.sh" in crontab_content, "Crontab does not contain the query_health.sh script"

    active = [line.strip() for line in crontab_content.splitlines()
              if line.strip() and not line.lstrip().startswith("#")]
    job_index = None
    env_index = None
    for index, line in enumerate(active):
        if re.fullmatch(r"LOG_DIR\s*=\s*/home/user/logs", line):
            env_index = index
        if re.match(r"^\*\s+\*\s+\*\s+\*\s+\*\s+.*(?:^|\s)/home/user/query_health\.sh(?:\s|$)", line):
            job_index = index
            break
    assert env_index is not None, "Crontab lacks an active LOG_DIR assignment"
    assert job_index is not None, "Crontab lacks an active every-minute query_health.sh job"
    assert env_index < job_index, "LOG_DIR must be assigned before the cron job"

    assert os.path.isfile(LOG_FILE), f"Log file {LOG_FILE} not found."
    with open(LOG_FILE) as handle:
        log_content = handle.read()
    assert "STATUS: OK" in log_content, f"Log file {LOG_FILE} does not contain 'STATUS: OK'"

    # Replace any pre-existing server and execute the submitted ELF itself.
    stop_existing_listener()
    subprocess.Popen(
        [HEALTHD],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    deadline = time.time() + 3
    while not listener_inodes() and time.time() < deadline:
        time.sleep(0.05)
    assert listener_inodes(), "Executing /home/user/healthd did not create a listener on port 8080"

    expected_exe = os.path.realpath(HEALTHD)
    owners = listener_pids()
    assert owners, "Could not identify the process serving port 8080"
    serving_exes = []
    for pid in owners:
        try:
            serving_exes.append(os.path.realpath(f"/proc/{pid}/exe"))
        except OSError:
            pass
    assert expected_exe in serving_exes, "/home/user/healthd is not the executable serving port 8080"

    # Exercise both outcomes using answers derived from controlled PID-file states.
    assert read_response() == b"STATUS: OK\n", "Submitted daemon did not return the exact healthy response"
    with open("/proc/sys/kernel/pid_max") as handle:
        impossible_pid = int(handle.read().strip()) + 1
    try:
        with open(PID_FILE, "w") as handle:
            handle.write(f"{impossible_pid}\n")
        assert not os.path.exists(f"/proc/{impossible_pid}")
        assert read_response() == b"STATUS: FAIL\n", "Daemon did not report FAIL for a nonexistent PID"
    finally:
        with open(PID_FILE, "w") as handle:
            handle.write(f"{worker_pid}\n")
    assert read_response() == b"STATUS: OK\n", "Daemon did not recover after restoring the live worker PID"

    # Run the cron command under a minimal cron-like environment and require fresh output.
    os.makedirs("/home/user/logs", exist_ok=True)
    try:
        os.unlink(LOG_FILE)
    except FileNotFoundError:
        pass
    cron_env = {
        "HOME": "/root",
        "LOGNAME": "root",
        "SHELL": "/bin/sh",
        "PATH": "/usr/bin:/bin",
        "LOG_DIR": "/home/user/logs",
    }
    query = subprocess.run(["/home/user/query_health.sh"], env=cron_env, timeout=5)
    assert query.returncode == 0, "query_health.sh failed under a minimal cron-like environment"
    assert os.path.isfile(LOG_FILE), "Cron query command did not create /home/user/logs/status.log"
    with open(LOG_FILE, "rb") as handle:
        assert handle.read() == b"STATUS: OK\n", "Cron query did not record the daemon's healthy response"
TEST_EOF

rc=0
python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1 || rc=$?
if [ "$rc" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
