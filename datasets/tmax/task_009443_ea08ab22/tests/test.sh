#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import signal
import socket
import subprocess
import time

import pytest

DEPLOY_SCRIPT = "/home/user/deploy.sh"
C_FILE = "/home/user/net_monitor.c"
BINARY_FILE = "/home/user/net_monitor"
PID_FILE = "/home/user/monitor.pid"
LOG_FILE = "/home/user/monitor_alerts.log"
BASHRC_FILE = "/home/user/.bashrc"
TEST_BINARY = "/tmp/net_monitor_from_source"


def stop_pid_from_file():
    if not os.path.isfile(PID_FILE):
        return
    try:
        with open(PID_FILE, "r") as f:
            value = f.read().strip()
        if value.isdigit():
            os.kill(int(value), signal.SIGKILL)
    except OSError:
        pass


def unused_port():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def test_deploy_script_exists_and_executable():
    assert os.path.isfile(DEPLOY_SCRIPT), f"{DEPLOY_SCRIPT} does not exist."
    assert os.access(DEPLOY_SCRIPT, os.X_OK), f"{DEPLOY_SCRIPT} is not executable."


def test_net_monitor_c_exists():
    assert os.path.isfile(C_FILE), f"{C_FILE} does not exist."


def test_c_source_compiles_and_obeys_dynamic_target_ports():
    compile_result = subprocess.run(
        ["gcc", C_FILE, "-o", TEST_BINARY],
        capture_output=True,
        text=True,
    )
    assert compile_result.returncode == 0, (
        f"gcc failed with exit code {compile_result.returncode}: {compile_result.stderr}"
    )
    assert os.path.isfile(TEST_BINARY), "Compiling net_monitor.c did not produce a binary."
    assert os.access(TEST_BINARY, os.X_OK), "Compiled net_monitor.c is not executable."

    ports = []
    while len(ports) < 2:
        port = unused_port()
        if port != 8080 and port not in ports:
            ports.append(port)

    for port in ports:
        if os.path.exists(LOG_FILE):
            os.remove(LOG_FILE)

        env = os.environ.copy()
        env["TARGET_PORT"] = str(port)
        started = time.monotonic()
        proc = subprocess.Popen(
            [TEST_BINARY],
            env=env,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            text=True,
        )
        try:
            _, stderr = proc.communicate(timeout=7)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.communicate()
            pytest.fail(f"Monitor did not exit after three failures on TARGET_PORT={port}.")

        elapsed = time.monotonic() - started
        assert proc.returncode == 0, (
            f"Monitor exited with {proc.returncode} for TARGET_PORT={port}. Stderr: {stderr}"
        )
        assert elapsed >= 1.5, "Monitor did not perform failure attempts at one-second intervals."
        assert os.path.isfile(LOG_FILE), f"{LOG_FILE} was not created for TARGET_PORT={port}."
        with open(LOG_FILE, "rb") as f:
            actual = f.read()
        expected = (
            f"[CRITICAL] Port {port} unresponsive. Executing container restart.\n"
        ).encode()
        assert actual == expected, (
            f"Alert for TARGET_PORT={port} was not the exact required line. Found: {actual!r}"
        )


def test_monitor_behavior():
    stop_pid_from_file()
    for path in (PID_FILE, LOG_FILE, BINARY_FILE):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    server_proc = subprocess.Popen(
        ["python3", "-m", "http.server", "8080", "--bind", "127.0.0.1"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    time.sleep(1)
    assert server_proc.poll() is None, "The test server could not start on port 8080."

    monitor_pid = None
    try:
        result = subprocess.run([DEPLOY_SCRIPT], capture_output=True, text=True)
        assert result.returncode == 0, (
            f"deploy.sh failed with exit code {result.returncode}. Stderr: {result.stderr}"
        )

        assert os.path.isfile(BASHRC_FILE), f"{BASHRC_FILE} does not exist."
        with open(BASHRC_FILE, "r") as f:
            bashrc_content = f.read()
        assert "export MONITOR_DEPLOYED=true" in bashrc_content, (
            f"export MONITOR_DEPLOYED=true not found in {BASHRC_FILE}."
        )

        assert os.path.isfile(BINARY_FILE), f"{BINARY_FILE} was not compiled."
        assert os.access(BINARY_FILE, os.X_OK), f"{BINARY_FILE} is not executable."

        assert os.path.isfile(PID_FILE), f"{PID_FILE} does not exist."
        with open(PID_FILE, "r") as f:
            pid_str = f.read().strip()
        assert pid_str.isdigit(), f"{PID_FILE} does not contain a valid numeric PID."
        monitor_pid = int(pid_str)

        try:
            os.kill(monitor_pid, 0)
        except OSError:
            pytest.fail(f"Process with PID {monitor_pid} from {PID_FILE} is not running.")

        server_proc.terminate()
        server_proc.wait(timeout=5)

        deadline = time.monotonic() + 7
        while time.monotonic() < deadline and not os.path.isfile(LOG_FILE):
            time.sleep(0.1)

        assert os.path.isfile(LOG_FILE), f"{LOG_FILE} does not exist after failures."
        with open(LOG_FILE, "rb") as f:
            log_content = f.read()
        expected_log = b"[CRITICAL] Port 8080 unresponsive. Executing container restart.\n"
        assert log_content == expected_log, (
            f"Log is not exactly the required alert line. Found: {log_content!r}"
        )
    finally:
        if server_proc.poll() is None:
            server_proc.terminate()
            server_proc.wait(timeout=5)
        if monitor_pid is not None:
            try:
                os.kill(monitor_pid, signal.SIGKILL)
            except OSError:
                pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
