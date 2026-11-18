#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import signal
import socket
import stat
import subprocess
import tempfile
import time

import pytest

SOURCE = "/home/user/monitor.c"
BINARY = "/home/user/monitor_service"
SCRIPT = "/home/user/manage_service.sh"
IMAGE = "/app/network_diagram.png"


def read_configuration():
    result = subprocess.run(
        ["tesseract", IMAGE, "stdout"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
        check=True,
    )
    text = result.stdout
    port_match = re.search(r"PORT\s*:\s*(\d+)", text, re.IGNORECASE)
    endpoint_match = re.search(r"ENDPOINT\s*:\s*(/\S+)", text, re.IGNORECASE)
    key_match = re.search(r"AUTH_KEY\s*:\s*(\S+)", text, re.IGNORECASE)
    assert port_match and endpoint_match and key_match, f"Could not extract configuration from image: {text!r}"
    return int(port_match.group(1)), endpoint_match.group(1), key_match.group(1)


PORT, ENDPOINT, AUTH_KEY = read_configuration()


def listening_socket_inodes(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r", encoding="ascii") as handle:
                lines = handle.readlines()[1:]
        except FileNotFoundError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) < 10:
                continue
            try:
                local_port = int(fields[1].rsplit(":", 1)[1], 16)
            except (ValueError, IndexError):
                continue
            if local_port == port and fields[3] == "0A":
                inodes.add(fields[9])
    return inodes


def listener_pids(port):
    inodes = listening_socket_inodes(port)
    if not inodes:
        return set()
    wanted = {f"socket:[{inode}]" for inode in inodes}
    owners = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    if os.readlink(f"{fd_dir}/{fd}") in wanted:
                        owners.add(int(entry))
                        break
                except (FileNotFoundError, PermissionError, OSError):
                    pass
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return owners


def wait_for_listener(port, timeout=5.0):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        pids = listener_pids(port)
        if pids:
            return pids
        time.sleep(0.05)
    return set()


def stop_port_listeners(port):
    pids = listener_pids(port)
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.monotonic() + 2.0
    while time.monotonic() < deadline and listener_pids(port):
        time.sleep(0.05)
    for pid in listener_pids(port):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    deadline = time.monotonic() + 2.0
    while time.monotonic() < deadline and listener_pids(port):
        time.sleep(0.05)
    assert not listener_pids(port), f"Could not stop the pre-existing listener on port {port}"


def assert_listener_is_binary(pids):
    assert pids, f"No process is listening on port {PORT}"
    for pid in pids:
        exe = f"/proc/{pid}/exe"
        try:
            assert os.path.samefile(exe, BINARY), (
                f"Listener PID {pid} is not running {BINARY}; it runs {os.readlink(exe)}"
            )
        except FileNotFoundError:
            pytest.fail(f"Listener PID {pid} disappeared unexpectedly")


def request(path):
    with socket.create_connection(("127.0.0.1", PORT), timeout=3.0) as sock:
        sock.settimeout(3.0)
        wire_request = f"GET {path} HTTP/1.0\r\nHost: 127.0.0.1\r\n\r\n".encode("ascii")
        sock.sendall(wire_request)
        chunks = []
        while True:
            chunk = sock.recv(4096)
            if not chunk:
                break
            chunks.append(chunk)
    response = b"".join(chunks)
    assert response, "Received empty response from the server."
    assert b"\r\n\r\n" in response, "Response does not contain a valid HTTP header/body separator."
    head, body = response.split(b"\r\n\r\n", 1)
    lines = head.split(b"\r\n")
    return response, lines[0], lines[1:], body


def test_c_source_exists():
    path = SOURCE
    assert os.path.exists(path), f"C source file {path} is missing."
    assert os.path.isfile(path), f"{path} is not a file."


def test_compiled_binary_exists():
    path = BINARY
    assert os.path.exists(path), f"Compiled binary {path} is missing."
    assert os.path.isfile(path), f"{path} is not a file."
    st = os.stat(path)
    assert bool(st.st_mode & stat.S_IXUSR), f"{path} is not executable."
    with open(path, "rb") as handle:
        assert handle.read(4) == b"\x7fELF", f"{path} is not a compiled ELF binary."


def test_manage_script_exists():
    path = SCRIPT
    assert os.path.exists(path), f"Bash script {path} is missing."
    assert os.path.isfile(path), f"{path} is not a file."
    st = os.stat(path)
    assert bool(st.st_mode & stat.S_IXUSR), f"{path} is not executable."


def test_c_source_compiles():
    with tempfile.TemporaryDirectory() as directory:
        output = os.path.join(directory, "monitor_from_source")
        result = subprocess.run(
            ["gcc", SOURCE, "-o", output],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=20,
        )
        assert result.returncode == 0, f"monitor.c does not compile:\n{result.stderr}"
        assert os.path.isfile(output) and os.access(output, os.X_OK)


@pytest.fixture(scope="session")
def managed_service():
    stop_port_listeners(PORT)

    direct = subprocess.Popen(
        [BINARY],
        cwd="/home/user",
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    direct_pids = wait_for_listener(PORT)
    try:
        assert direct_pids, f"{BINARY} did not listen on port {PORT} when executed directly"
        assert_listener_is_binary(direct_pids)
    finally:
        stop_port_listeners(PORT)
        try:
            os.killpg(direct.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass

    first = subprocess.run(
        [SCRIPT],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert first.returncode == 0, f"Management script failed to start the service: {first.stderr}"
    first_pids = wait_for_listener(PORT)
    assert first_pids, f"Management script did not start a listener on port {PORT}"
    assert_listener_is_binary(first_pids)

    second = subprocess.run(
        [SCRIPT],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert second.returncode == 0, f"Second management-script invocation failed: {second.stderr}"
    time.sleep(0.3)
    second_pids = listener_pids(PORT)
    assert second_pids == first_pids, (
        "Management script is not idempotent: a second invocation replaced or duplicated the listener"
    )
    assert_listener_is_binary(second_pids)

    yield second_pids
    # Intentionally leave the verified service running.


def test_manage_script_functional_and_idempotent(managed_service):
    assert managed_service


def test_service_valid_endpoint(managed_service):
    response, status_line, headers, body = request(ENDPOINT)
    assert b"200" in status_line, f"Expected 200 OK status, got: {status_line!r}"
    assert AUTH_KEY.encode() in response, f"Expected AUTH_KEY '{AUTH_KEY}' not found in response."
    assert status_line == b"HTTP/1.0 200 OK", f"Expected exact HTTP/1.0 200 OK status, got: {status_line!r}"
    content_types = [h.split(b":", 1)[1].strip().lower() for h in headers if h.lower().startswith(b"content-type:")]
    assert content_types and content_types[0].startswith(b"text/plain"), "Successful response is not plain text"
    assert body == (AUTH_KEY + "\n").encode(), f"Response body must contain exactly AUTH_KEY followed by a newline; got {body!r}"


def test_service_invalid_endpoint(managed_service):
    invalid_paths = [
        "/invalid_path_123",
        "/invalid_" + secrets.token_hex(12),
        ENDPOINT + "/" + secrets.token_hex(8),
    ]
    for path in invalid_paths:
        response, status_line, _headers, _body = request(path)
        assert b"404" in status_line, f"Expected 404 Not Found status for {path}, got: {status_line!r}"
        assert status_line == b"HTTP/1.0 404 Not Found", f"Expected exact HTTP/1.0 404 Not Found status, got: {status_line!r}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
