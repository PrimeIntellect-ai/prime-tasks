#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import signal
import socket
import subprocess
import threading
import time
import uuid

import pytest

USER = pwd.getpwnam("user")
USER_ENV = {
    **os.environ,
    "HOME": "/home/user",
    "USER": "user",
    "LOGNAME": "user",
}


def demote_user(new_session=False):
    def fn():
        if new_session:
            os.setsid()
        os.setgroups([])
        os.setgid(USER.pw_gid)
        os.setuid(USER.pw_uid)
    return fn


def run_as_user(path, timeout=15):
    return subprocess.run(
        [path],
        env=USER_ENV,
        preexec_fn=demote_user(),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=timeout,
    )


def test_00_deploy_script_exists_is_executable_and_idempotent():
    script_path = "/home/user/deploy.sh"
    assert os.path.isfile(script_path), f"Script {script_path} is missing."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."

    for attempt in (1, 2):
        result = run_as_user(script_path)
        assert result.returncode == 0, (
            f"deploy.sh failed on run {attempt}: stdout={result.stdout!r}, "
            f"stderr={result.stderr!r}"
        )
        assert os.path.islink("/home/user/app_current")
        assert os.readlink("/home/user/app_current") == "/home/user/releases/v2"
        assert os.path.isdir("/home/user/logs")


def test_symlink_app_current():
    """Test that /home/user/app_current is a symlink pointing to /home/user/releases/v2."""
    symlink_path = "/home/user/app_current"
    target_path = "/home/user/releases/v2"

    assert os.path.islink(symlink_path), f"{symlink_path} is not a symlink."
    assert os.readlink(symlink_path) == target_path, f"{symlink_path} does not point to {target_path}."


def test_logs_directory_exists():
    """Test that /home/user/logs directory exists."""
    logs_dir = "/home/user/logs"
    assert os.path.isdir(logs_dir), f"Directory {logs_dir} is missing."


def test_start_proxy_script():
    """Test that start_proxy.sh has the required text and actually proxies 8080 to 8081."""
    script_path = "/home/user/start_proxy.sh"

    assert os.path.isfile(script_path), f"Script {script_path} is missing."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."

    with open(script_path, "r") as f:
        content = f.read()

    assert "socat" in content, f"{script_path} does not contain 'socat'."
    assert "8080" in content, f"{script_path} does not contain port '8080'."
    assert "8081" in content, f"{script_path} does not contain port '8081'."

    # Remove any service left by the agent so this test exercises this script.
    subprocess.run(["pkill", "-u", "user", "socat"], stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL, check=False)
    time.sleep(0.2)

    payload = ("proxy-test-" + uuid.uuid4().hex).encode()
    expected = payload[::-1]
    backend_errors = []
    ready = threading.Event()

    def backend():
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as server:
                server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
                server.bind(("127.0.0.1", 8081))
                server.listen(1)
                server.settimeout(8)
                ready.set()
                conn, _ = server.accept()
                with conn:
                    conn.settimeout(5)
                    data = conn.recv(4096)
                    conn.sendall(data[::-1])
        except Exception as exc:
            backend_errors.append(exc)
            ready.set()

    thread = threading.Thread(target=backend, daemon=True)
    thread.start()
    assert ready.wait(3), "Backend test server did not start."
    assert not backend_errors, f"Backend test server failed: {backend_errors!r}"

    proc = subprocess.Popen(
        [script_path],
        env=USER_ENV,
        preexec_fn=demote_user(new_session=True),
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    try:
        deadline = time.time() + 6
        response = None
        last_error = None
        while time.time() < deadline:
            try:
                with socket.create_connection(("127.0.0.1", 8080), timeout=0.5) as client:
                    client.settimeout(3)
                    client.sendall(payload)
                    client.shutdown(socket.SHUT_WR)
                    response = client.recv(4096)
                    break
            except OSError as exc:
                last_error = exc
                time.sleep(0.1)
        assert response is not None, f"Nothing listened on port 8080: {last_error}"
        assert response == expected, "Traffic on port 8080 was not forwarded to the test server on 8081."
        thread.join(3)
        assert not backend_errors, f"Backend test server failed: {backend_errors!r}"
    finally:
        try:
            os.killpg(proc.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        subprocess.run(["pkill", "-u", "user", "socat"], stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL, check=False)
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            proc.kill()


def test_start_worker_script():
    """Test that start_worker.sh has the required configuration and actually runs the worker."""
    script_path = "/home/user/start_worker.sh"

    assert os.path.isfile(script_path), f"Script {script_path} is missing."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."

    with open(script_path, "r") as f:
        content = f.read()

    assert "Europe/Berlin" in content, f"{script_path} does not set TZ to 'Europe/Berlin'."
    assert "en_US.UTF-8" in content, f"{script_path} does not set LC_ALL to 'en_US.UTF-8'."

    log_path = "/home/user/logs/worker_output.log"
    try:
        os.unlink(log_path)
    except FileNotFoundError:
        pass

    result = run_as_user(script_path)
    assert result.returncode == 0, (
        f"start_worker.sh failed: stdout={result.stdout!r}, stderr={result.stderr!r}"
    )

    deadline = time.time() + 5
    while time.time() < deadline and not os.path.isfile(log_path):
        time.sleep(0.05)
    assert os.path.isfile(log_path), "start_worker.sh did not create worker_output.log."

    expected = (
        "Version: v2\n"
        "TZ: Europe/Berlin\n"
        "LC_ALL: en_US.UTF-8\n"
        "CWD: /home/user/logs\n"
    )
    deadline = time.time() + 5
    actual = ""
    while time.time() < deadline:
        with open(log_path, "r") as f:
            actual = f.read()
        if actual == expected:
            break
        time.sleep(0.05)
    assert actual == expected, f"Worker produced unexpected output: {actual!r}"


def test_worker_output_log():
    """Test that /home/user/logs/worker_output.log exists and contains the correct output."""
    log_path = "/home/user/logs/worker_output.log"

    assert os.path.isfile(log_path), f"Log file {log_path} is missing. Did the worker script run successfully?"

    with open(log_path, "r") as f:
        content = f.read()

    assert "Version: v2" in content, "Log file does not contain 'Version: v2'."
    assert "TZ: Europe/Berlin" in content, "Log file does not contain 'TZ: Europe/Berlin'."
    assert "LC_ALL: en_US.UTF-8" in content, "Log file does not contain 'LC_ALL: en_US.UTF-8'."
    assert "CWD: /home/user/logs" in content, "Log file does not contain 'CWD: /home/user/logs'. Working directory was not changed correctly."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
