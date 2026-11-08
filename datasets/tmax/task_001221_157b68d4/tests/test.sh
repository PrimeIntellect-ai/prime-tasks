#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import socket
import subprocess
import time
import pytest

SERVER_CODE = r'''
import socket
import sys

server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
server.bind(("127.0.0.1", 8081))
server.listen(5)
print("READY", flush=True)
while True:
    client, _ = server.accept()
    try:
        data = client.recv(1024)
        if data == b"PING\n":
            client.sendall(b"PONG\n")
    finally:
        client.close()
'''

def start_test_server():
    proc = subprocess.Popen(
        ["python3", "-c", SERVER_CODE],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    ready = proc.stdout.readline().strip()
    if ready != "READY":
        stderr = proc.stderr.read()
        proc.wait(timeout=5)
        pytest.fail(f"Failed to start test service on port 8081: {stderr}")
    return proc

def stop_test_server(proc):
    if proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=5)
    time.sleep(0.1)

def test_health_checker_exists_and_executable():
    """Verify that the compiled health_checker exists and is executable."""
    checker_path = "/home/user/health_checker"
    assert os.path.exists(checker_path), f"{checker_path} does not exist."
    assert os.path.isfile(checker_path), f"{checker_path} is not a file."
    assert os.access(checker_path, os.X_OK), f"{checker_path} is not executable."

def test_health_checker_behavior():
    """Verify the health_checker binary exits with correct codes."""
    checker_path = "/home/user/health_checker"

    server = start_test_server()
    try:
        result_up = subprocess.run([checker_path, "8081"], capture_output=True)
        assert result_up.returncode == 0, f"Expected exit code 0 for port 8081, got {result_up.returncode}"
    finally:
        stop_test_server(server)

    # Find a free port for DOWN test.
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("127.0.0.1", 0))
        free_port = s.getsockname()[1]

    result_down = subprocess.run([checker_path, str(free_port)], capture_output=True)
    assert result_down.returncode == 1, f"Expected exit code 1 for closed port {free_port}, got {result_down.returncode}"

def test_monitor_sh_behavior():
    """Verify monitor.sh script logic."""
    monitor_path = "/home/user/monitor.sh"
    log_path = "/home/user/health.log"

    assert os.path.exists(monitor_path), f"{monitor_path} does not exist."
    assert os.access(monitor_path, os.X_OK), f"{monitor_path} is not executable."

    if os.path.exists(log_path):
        os.remove(log_path)

    server = start_test_server()
    try:
        subprocess.run([monitor_path], check=True)

        assert os.path.exists(log_path), f"{log_path} was not created."
        with open(log_path, "r") as f:
            lines = f.readlines()
        assert len(lines) >= 1, "Log file is empty."
        assert lines[-1] == "UP\n", f"Expected last line to be 'UP\\n', got {repr(lines[-1])}"
    finally:
        stop_test_server(server)

    subprocess.run([monitor_path], check=False)

    with open(log_path, "r") as f:
        lines = f.readlines()
    assert len(lines) >= 2, "Log file did not append new status."
    assert lines[-1] == "DOWN\n", f"Expected last line to be 'DOWN\\n', got {repr(lines[-1])}"

def test_cron_job():
    """Verify the cron job is installed for the user account."""
    try:
        result = subprocess.run(["crontab", "-u", "user", "-l"], capture_output=True, text=True)
        if result.returncode != 0:
            result = subprocess.run(["crontab", "-l"], capture_output=True, text=True)

        assert result.returncode == 0, "Failed to read crontab."

        cron_lines = [
            line.strip()
            for line in result.stdout.split("\n")
            if line.strip() and not line.startswith("#")
        ]

        found = False
        for line in cron_lines:
            parts = line.split()
            if len(parts) >= 6:
                schedule = " ".join(parts[:5])
                command = " ".join(parts[5:])
                if schedule == "* * * * *" and "/home/user/monitor.sh" in command:
                    found = True
                    break

        assert found, "Could not find cron entry matching '* * * * * /home/user/monitor.sh'"
    except FileNotFoundError:
        pytest.fail("crontab command not found")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
