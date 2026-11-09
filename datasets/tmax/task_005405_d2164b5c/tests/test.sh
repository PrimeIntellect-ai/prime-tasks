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
import secrets
import signal
import socket
import stat
import time

import pytest
import requests

HTTP_PORT = 9080
TCP_PORT = 9081
SECRET = "BGP456"
BASE = "/home/user/diag_service"
ACCESS_LOG = f"{BASE}/logs/access.log"
SERVER_SCRIPT = f"{BASE}/bin/diag_server.py"
START_SCRIPT = f"{BASE}/bin/start.sh"
PID_FILE = f"{BASE}/run/service.pid"


def log_size():
    try:
        return os.path.getsize(ACCESS_LOG)
    except FileNotFoundError:
        return 0


def assert_log_grew(previous_size):
    deadline = time.time() + 2
    while time.time() < deadline:
        if log_size() > previous_size:
            return
        time.sleep(0.05)
    pytest.fail("access.log did not grow for a connection attempt")


def read_pid():
    assert os.path.isfile(PID_FILE), f"{PID_FILE} does not exist"
    with open(PID_FILE, "r") as f:
        value = f.read().strip()
    try:
        return int(value)
    except ValueError:
        pytest.fail(f"PID file {PID_FILE} does not contain a valid integer: {value}")


def process_args(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            return [x.decode(errors="replace") for x in f.read().split(b"\0") if x]
    except (FileNotFoundError, ProcessLookupError, PermissionError):
        return []


def process_mentions_path(pid, expected):
    args = process_args(pid)
    try:
        cwd = os.readlink(f"/proc/{pid}/cwd")
    except OSError:
        cwd = "/"
    expected = os.path.realpath(expected)
    for arg in args:
        if not arg or arg.startswith("-"):
            continue
        candidate = arg if os.path.isabs(arg) else os.path.join(cwd, arg)
        if os.path.realpath(candidate) == expected:
            return True
    return False


def parent_pid(pid):
    try:
        with open(f"/proc/{pid}/status", "r") as f:
            for line in f:
                if line.startswith("PPid:"):
                    return int(line.split()[1])
    except (FileNotFoundError, ProcessLookupError, ValueError):
        pass
    return 0


def has_start_supervisor_ancestor(pid):
    current = parent_pid(pid)
    for _ in range(6):
        if current <= 1:
            return False
        if process_mentions_path(current, START_SCRIPT):
            return True
        current = parent_pid(current)
    return False


def listening_inodes():
    wanted = {HTTP_PORT, TCP_PORT}
    found = {}
    with open("/proc/net/tcp", "r") as f:
        next(f)
        for line in f:
            fields = line.split()
            local, state, inode = fields[1], fields[3], fields[9]
            address, port_hex = local.split(":")
            port = int(port_hex, 16)
            if state == "0A" and address == "0100007F" and port in wanted:
                found[port] = inode
    return found


def pid_socket_inodes(pid):
    result = set()
    try:
        names = os.listdir(f"/proc/{pid}/fd")
    except (FileNotFoundError, ProcessLookupError, PermissionError):
        return result
    for name in names:
        try:
            target = os.readlink(f"/proc/{pid}/fd/{name}")
        except OSError:
            continue
        if target.startswith("socket:[") and target.endswith("]"):
            result.add(target[8:-1])
    return result


def assert_pid_is_server(pid):
    assert process_mentions_path(pid, SERVER_SCRIPT), f"PID {pid} is not running {SERVER_SCRIPT}"
    listeners = listening_inodes()
    assert set(listeners) == {HTTP_PORT, TCP_PORT}, "Both required loopback listeners are not active"
    owned = pid_socket_inodes(pid)
    for port in (HTTP_PORT, TCP_PORT):
        assert listeners[port] in owned, f"PID {pid} does not own the listener on port {port}"
    assert has_start_supervisor_ancestor(pid), f"PID {pid} is not supervised by {START_SCRIPT}"


def recv_exact(sock, expected_length):
    chunks = []
    remaining = expected_length
    while remaining:
        chunk = sock.recv(remaining)
        if not chunk:
            break
        chunks.append(chunk)
        remaining -= len(chunk)
    return b"".join(chunks)


def rejected_tcp_auth(auth_line):
    before = log_size()
    received = b""
    s = socket.create_connection(("127.0.0.1", TCP_PORT), timeout=2)
    s.settimeout(1)
    try:
        try:
            s.sendall(auth_line + b"\nPING\n")
            received = s.recv(1024)
        except (ConnectionResetError, BrokenPipeError):
            received = b""
        except socket.timeout:
            pytest.fail("Invalid TCP authentication was not immediately rejected")
    finally:
        s.close()
    assert received == b"", f"Expected connection to be dropped, but received {received!r}"
    assert_log_grew(before)


def test_directory_structure_and_artifacts():
    for directory in (f"{BASE}/bin", f"{BASE}/logs", f"{BASE}/run"):
        assert os.path.isdir(directory), f"Directory {directory} does not exist"

    symlink_path = f"{BASE}/current_logs"
    assert os.path.islink(symlink_path), f"{symlink_path} is not a symlink"
    assert os.readlink(symlink_path) == f"{BASE}/logs", f"Symlink {symlink_path} does not point to {BASE}/logs"

    assert os.path.isfile(SERVER_SCRIPT) and not os.path.islink(SERVER_SCRIPT), f"{SERVER_SCRIPT} is not a regular file"
    assert os.path.isfile(START_SCRIPT) and not os.path.islink(START_SCRIPT), f"{START_SCRIPT} is not a regular file"
    assert stat.S_IMODE(os.stat(START_SCRIPT).st_mode) & 0o111, f"{START_SCRIPT} is not executable"


def test_http_server_and_connection_logging():
    url = f"http://127.0.0.1:{HTTP_PORT}/status"

    before = log_size()
    response = requests.get(url, headers={"X-Diag-Secret": SECRET, "Connection": "close"}, timeout=2)
    assert response.status_code == 200, f"Expected status 200, got {response.status_code}"
    try:
        assert response.json() == {"status": "UP"}, f"Unexpected JSON response: {response.text}"
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")
    response.close()
    assert_log_grew(before)

    before = log_size()
    response_wrong = requests.get(url, headers={"X-Diag-Secret": "WRONG", "Connection": "close"}, timeout=2)
    assert response_wrong.status_code == 401, f"Expected status 401 for wrong secret, got {response_wrong.status_code}"
    response_wrong.close()
    assert_log_grew(before)

    random_wrong = secrets.token_urlsafe(24)
    assert random_wrong != SECRET
    before = log_size()
    response_random = requests.get(url, headers={"X-Diag-Secret": random_wrong, "Connection": "close"}, timeout=2)
    assert response_random.status_code == 401, f"Expected status 401 for random wrong secret, got {response_random.status_code}"
    response_random.close()
    assert_log_grew(before)

    before = log_size()
    response_missing = requests.get(url, headers={"Connection": "close"}, timeout=2)
    assert response_missing.status_code == 401, f"Expected status 401 for missing secret, got {response_missing.status_code}"
    response_missing.close()
    assert_log_grew(before)


def test_tcp_server_and_connection_logging():
    before = log_size()
    s = socket.create_connection(("127.0.0.1", TCP_PORT), timeout=2)
    s.settimeout(2)
    try:
        s.sendall(f"AUTH {SECRET}\n".encode())
        time.sleep(0.05)
        s.sendall(b"PING\n")
        data = recv_exact(s, len(b"PING\n"))
        assert b"PING" in data, f"Expected 'PING' in response, got {data!r}"
    finally:
        s.close()
    assert_log_grew(before)

    lines = [
        f"alpha-{secrets.token_hex(13)}",
        f"message with spaces {secrets.token_hex(17)}",
        f"omega-{secrets.token_urlsafe(31)}",
    ]
    payload = ("\n".join(lines) + "\n").encode()
    before = log_size()
    s = socket.create_connection(("127.0.0.1", TCP_PORT), timeout=2)
    s.settimeout(2)
    try:
        s.sendall(f"AUTH {SECRET}\n".encode())
        time.sleep(0.05)
        s.sendall(payload)
        echoed = recv_exact(s, len(payload))
        assert echoed == payload, f"Random subsequent lines were not echoed exactly: {echoed!r}"
    finally:
        s.close()
    assert_log_grew(before)

    rejected_tcp_auth(b"AUTH INVALID")
    random_invalid = secrets.token_urlsafe(28)
    assert random_invalid != SECRET
    rejected_tcp_auth(f"AUTH {random_invalid}".encode())


def test_logging_and_supervisor_restart():
    service_log = f"{BASE}/logs/service.log"
    assert os.path.isfile(ACCESS_LOG), f"{ACCESS_LOG} does not exist"
    assert os.path.getsize(ACCESS_LOG) > 0, f"{ACCESS_LOG} is empty"
    assert os.path.isfile(service_log), f"{service_log} does not exist"

    old_pid = read_pid()
    assert_pid_is_server(old_pid)
    old_owned = pid_socket_inodes(old_pid)

    os.kill(old_pid, signal.SIGTERM)

    new_pid = None
    deadline = time.time() + 3
    while time.time() < deadline:
        try:
            candidate = read_pid()
            if candidate != old_pid:
                assert_pid_is_server(candidate)
                new_pid = candidate
                break
        except (AssertionError, OSError):
            pass
        time.sleep(0.05)

    assert new_pid is not None, "Supervisor did not replace the terminated diagnostic server process"
    assert not (old_owned & pid_socket_inodes(old_pid)), "The terminated PID still owns the service sockets"

    before = log_size()
    response = requests.get(
        f"http://127.0.0.1:{HTTP_PORT}/status",
        headers={"X-Diag-Secret": SECRET, "Connection": "close"},
        timeout=2,
    )
    assert response.status_code == 200, "HTTP server did not restart properly"
    assert response.json() == {"status": "UP"}
    response.close()
    assert_log_grew(before)

    before = log_size()
    s = socket.create_connection(("127.0.0.1", TCP_PORT), timeout=2)
    s.close()
    assert_log_grew(before)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
