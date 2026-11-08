#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import signal
import socket
import string
import subprocess
import time

import pytest
import requests

REPO = "/app/bash-http-server"
SERVER = os.path.join(REPO, "server.sh")
SERVER_PROCESS = None


def get_bad_commit():
    cmd = ["git", "log", "-S", "fuzz-crash", "--format=%H", "--reverse"]
    result = subprocess.run(cmd, cwd=REPO, capture_output=True, text=True)
    commits = result.stdout.strip().splitlines()
    return commits[0] if commits else None


def listener_pids(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9 and fields[3] == "0A":
                        local_port = int(fields[1].rsplit(":", 1)[1], 16)
                        if local_port == port:
                            inodes.add(fields[9])
        except OSError:
            pass

    pids = set()
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(name))
                    break
        except OSError:
            pass
    return pids


def stop_existing_listener():
    for pid in listener_pids(9090):
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while listener_pids(9090) and time.time() < deadline:
        time.sleep(0.05)
    for pid in listener_pids(9090):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def wait_for_server():
    deadline = time.time() + 5
    while time.time() < deadline:
        if SERVER_PROCESS.poll() is not None:
            pytest.fail("The vendored server.sh exited instead of serving on port 9090.")
        try:
            with socket.create_connection(("127.0.0.1", 9090), timeout=0.2):
                return
        except OSError:
            time.sleep(0.05)
    pytest.fail("The executed vendored server.sh did not listen on 127.0.0.1:9090.")


@pytest.fixture(scope="session", autouse=True)
def execute_vendored_server():
    global SERVER_PROCESS
    assert os.path.isfile(SERVER), f"{SERVER} does not exist"
    assert not os.path.islink(SERVER), f"{SERVER} must be the repaired vendored script, not a symlink"
    assert os.access(SERVER, os.X_OK), f"{SERVER} is not executable"

    with open(SERVER, errors="replace") as f:
        source = f.read()
    assert source.startswith("#!/bin/bash") or source.startswith("#!/usr/bin/env bash"), "server.sh is not a bash server"
    assert "handle_request" in source and "socat" in source, "The vendored bash server implementation was replaced"
    assert not re.search(r"while\s+true\s*;?\s*do\s+sleep\s+0\.1\s*;?\s*done\s*\)\s*&", source, re.S), \
        "The leaking background loop is still present in server.sh"

    stop_existing_listener()
    SERVER_PROCESS = subprocess.Popen(
        [SERVER], cwd=REPO, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    wait_for_server()
    yield
    # Deliberately leave the verified vendored service running as required.


def test_bad_commit_identified():
    bad_commit_file = "/home/user/bad_commit.txt"
    assert os.path.isfile(bad_commit_file), f"File {bad_commit_file} does not exist. Did you save the bad commit hash?"
    with open(bad_commit_file) as f:
        student_commit = f.read().strip()
    expected_commit = get_bad_commit()
    assert expected_commit is not None, "Could not find the bad commit in the repository history."
    assert student_commit == expected_commit, f"Expected bad commit {expected_commit}, but got {student_commit}."
    assert re.fullmatch(r"[0-9a-f]{40}", student_commit), "The bad commit must be a full 40-character hash."


def test_server_responds_ok():
    try:
        response = requests.get("http://127.0.0.1:9090/", timeout=5)
        assert response.status_code == 200, f"Expected status code 200, got {response.status_code}."
        assert response.text.strip() == "OK", f"Expected body 'OK', got '{response.text}'."
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to server on 127.0.0.1:9090: {e}")


def get_sleep_processes():
    result = subprocess.run(["pgrep", "-f", "sleep 0.1"], capture_output=True, text=True)
    return set(result.stdout.strip().splitlines()) if result.stdout.strip() else set()


def test_server_no_process_leak():
    initial_procs = get_sleep_processes()
    try:
        requests.get("http://127.0.0.1:9090/compute", headers={"User-Agent": "fuzz-crash-test"}, timeout=2)
    except requests.exceptions.RequestException:
        pass
    time.sleep(2)
    new_procs = get_sleep_processes() - initial_procs
    assert len(new_procs) == 0, "Found leaked background processes after sending malicious request."


def relevant_processes():
    found = {}
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        try:
            with open(f"/proc/{name}/cmdline", "rb") as f:
                cmd = f.read().replace(b"\0", b" ").decode(errors="replace")
        except OSError:
            continue
        if "sleep 0.1" in cmd or "bash -c handle_request" in cmd:
            found[int(name)] = cmd
    return found


def raw_request(payload):
    try:
        with socket.create_connection(("127.0.0.1", 9090), timeout=1) as sock:
            if payload:
                sock.sendall(payload)
            sock.shutdown(socket.SHUT_WR)
            sock.settimeout(0.5)
            try:
                sock.recv(4096)
            except OSError:
                pass
    except OSError:
        pass


def test_compute_fuzz_and_dropped_requests_do_not_leak():
    before = relevant_processes()
    alphabet = string.ascii_letters + string.digits + "-_/.;()"
    random_text = lambda n: ''.join(secrets.choice(alphabet) for _ in range(n))
    user_agents = [
        "fuzz-crash",
        random_text(12) + "fuzz-crash" + random_text(12),
        "fuzz-crash-" + random_text(30),
        random_text(64),
        "",
        "../../" + random_text(20),
    ]
    for ua in user_agents:
        response = requests.get("http://127.0.0.1:9090/compute", headers={"User-Agent": ua}, timeout=2)
        assert response.status_code == 200
        assert response.text.strip() == "COMPUTE"

    raw_request(b"")
    raw_request(b"GET /compute HTTP/1.1\r\n")
    raw_request(b"GET /compute HTTP/1.1\r\nUser-Agent: fuzz-crash-")
    raw_request(b"malformed request\r\nUser-Agent: fuzz-crash\r\n\r\n")
    raw_request(b"GET /compute HTTP/1.1\nUser-Agent: " + random_text(32).encode() + b"\n\n")

    time.sleep(2)
    after = relevant_processes()
    leaked = {pid: cmd for pid, cmd in after.items() if pid not in before}
    assert not leaked, f"Requests left background handler/loop processes behind: {leaked}"
    assert SERVER_PROCESS.poll() is None, "The vendored server stopped while handling malformed requests"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
