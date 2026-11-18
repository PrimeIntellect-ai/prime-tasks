#!/bin/bash
mkdir -p /logs/verifier

cat <<'PYTEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import random
import secrets
import signal
import socket
import string
import subprocess
import tempfile
import time

import pytest

SERVICE_DIR = "/home/user/log_service"
SOURCE = os.path.join(SERVICE_DIR, "logd.c")
PORT = 8888
USER = pwd.getpwnam("user")


def demote():
    os.setgroups([])
    os.setgid(USER.pw_gid)
    os.setuid(USER.pw_uid)


def run_as_user(args, cwd, timeout):
    return subprocess.run(
        args,
        cwd=cwd,
        capture_output=True,
        text=True,
        timeout=timeout,
        preexec_fn=demote,
    )


def kill_port_listeners(port):
    wanted = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) < 10:
                        continue
                    local = fields[1]
                    state = fields[3]
                    inode = fields[9]
                    try:
                        local_port = int(local.rsplit(":", 1)[1], 16)
                    except (ValueError, IndexError):
                        continue
                    if local_port == port and state == "0A":
                        wanted.add("socket:[%s]" % inode)
        except FileNotFoundError:
            pass

    if not wanted:
        return

    for entry in os.listdir("/proc"):
        if not entry.isdigit() or int(entry) == os.getpid():
            continue
        fd_dir = os.path.join("/proc", entry, "fd")
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target in wanted:
                    try:
                        os.kill(int(entry), signal.SIGKILL)
                    except (ProcessLookupError, PermissionError):
                        pass
                    break
        except (FileNotFoundError, PermissionError):
            pass
    time.sleep(0.2)


def exchange(payload, timeout=3):
    with socket.create_connection(("127.0.0.1", PORT), timeout=timeout) as sock:
        sock.settimeout(timeout)
        if payload:
            sock.sendall(payload)
        sock.shutdown(socket.SHUT_WR)
        chunks = []
        while True:
            data = sock.recv(4096)
            if not data:
                break
            chunks.append(data)
        return b"".join(chunks)


def wait_for_server(proc):
    deadline = time.time() + 5
    while time.time() < deadline:
        assert proc.poll() is None, "The independently compiled logd exited before accepting connections"
        try:
            with socket.create_connection(("127.0.0.1", PORT), timeout=0.2):
                return
        except OSError:
            time.sleep(0.05)
    pytest.fail("The independently compiled logd did not listen on port 8888")


def test_fix_summary_exists():
    path = "/home/user/fix_summary.txt"
    assert os.path.isfile(path), f"The file {path} is missing. Did you create it?"
    with open(path, "r") as f:
        content = f.read().strip()
    assert len(content) > 10, f"The file {path} seems empty or too short. Please provide a brief explanation of both fixes."


def test_make_and_supplied_tests_pass():
    assert os.path.isdir(SERVICE_DIR), f"Directory {SERVICE_DIR} is missing."
    try:
        compile_result = run_as_user(["/usr/bin/make"], SERVICE_DIR, 20)
    except subprocess.TimeoutExpired:
        pytest.fail("Running 'make' timed out")
    assert compile_result.returncode == 0, f"Compilation failed:\n{compile_result.stdout}\n{compile_result.stderr}"

    try:
        test_result = run_as_user(["/usr/bin/make", "test"], SERVICE_DIR, 20)
    except subprocess.TimeoutExpired:
        pytest.fail("Running 'make test' timed out. The deadlock issue is likely not fixed.")
    assert test_result.returncode == 0, (
        f"'make test' failed.\nSTDOUT:\n{test_result.stdout}\nSTDERR:\n{test_result.stderr}"
    )


def test_source_and_daemon_behavior_independently():
    assert os.path.isfile(SOURCE), f"{SOURCE} is missing."
    assert not os.path.islink(SOURCE), f"{SOURCE} must be an actual source file, not a symbolic link."
    with open(SOURCE, "r") as f:
        content = f.read()
    assert "pthread_mutex_unlock" in content, "Could not find 'pthread_mutex_unlock' in logd.c."

    kill_port_listeners(PORT)
    work = tempfile.mkdtemp(prefix="logd_verify_")
    os.chown(work, USER.pw_uid, USER.pw_gid)
    binary = os.path.join(work, "logd_checked")

    try:
        result = run_as_user(
            ["/usr/bin/gcc", "-Wall", "-pthread", "-o", binary, SOURCE],
            work,
            20,
        )
        assert result.returncode == 0, (
            "Independent compilation of logd.c failed:\n"
            f"STDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
        )
        assert os.path.isfile(binary) and os.access(binary, os.X_OK), "Compilation did not produce an executable daemon"

        proc = subprocess.Popen(
            [binary],
            cwd=work,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            preexec_fn=demote,
        )
        try:
            wait_for_server(proc)
            alphabet = string.ascii_letters + string.digits
            token = "".join(secrets.choice(alphabet) for _ in range(18))
            level1 = "I" + "".join(random.choice(string.ascii_uppercase) for _ in range(6))
            level2 = "W" + "".join(random.choice(string.ascii_uppercase) for _ in range(6))
            level3 = "D" + "".join(random.choice(string.ascii_uppercase) for _ in range(6))
            normal = "normal-" + token
            after_bad = "after-malformed-" + token
            after_empty = "after-empty-" + token
            bracketed = "[System-" + token + "] started"

            assert exchange(f"[{level1}] {normal}\n".encode()) == b"OK\n"

            # The malformed request must finish, and a following valid request must
            # still be processed rather than blocking on the mutex.
            exchange(("malformed-" + token + "\n").encode())
            assert exchange(f"[{level2}] {after_bad}\n".encode()) == b"OK\n"

            # Also exercise a connection that supplies no log data.
            exchange(b"")
            assert exchange(f"[{level3}] {after_empty}\n".encode()) == b"OK\n"

            edge_level = "E" + "".join(random.choice(string.ascii_uppercase) for _ in range(6))
            assert exchange(f"[{edge_level}] {bracketed}\n".encode()) == b"OK\n"

            log_path = os.path.join(work, "server.log")
            deadline = time.time() + 2
            while time.time() < deadline and not os.path.isfile(log_path):
                time.sleep(0.02)
            assert os.path.isfile(log_path), "The daemon did not create server.log"
            with open(log_path, "r") as f:
                log = f.read()

            assert f"Logged [{level1}]: {normal}" in log
            assert f"Logged [{level2}]: {after_bad}" in log, "The daemon stopped processing after malformed input"
            assert f"Logged [{level3}]: {after_empty}" in log, "The daemon stopped processing after an empty connection"
            assert f"Logged [{edge_level}]: {bracketed}" in log, "A message beginning with '[' was rejected or changed"
            assert proc.poll() is None, "The daemon exited during behavioral testing"
        finally:
            if proc.poll() is None:
                proc.terminate()
                try:
                    proc.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    proc.kill()
                    proc.wait(timeout=2)
    finally:
        kill_port_listeners(PORT)
PYTEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
