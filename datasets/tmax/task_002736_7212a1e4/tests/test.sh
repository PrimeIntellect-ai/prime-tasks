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
mkdir -p /logs/verifier

cleanup_ports() {
python3 - <<'PY'
import os
import signal
import time

ports = {8080, 9090}
inodes = set()
for table in ("/proc/net/tcp", "/proc/net/tcp6"):
    try:
        with open(table) as f:
            next(f, None)
            for line in f:
                fields = line.split()
                if len(fields) < 10 or fields[3] != "0A":
                    continue
                try:
                    port = int(fields[1].rsplit(":", 1)[1], 16)
                except (ValueError, IndexError):
                    continue
                if port in ports:
                    inodes.add(fields[9])
    except FileNotFoundError:
        pass

victims = set()
for pid in os.listdir("/proc"):
    if not pid.isdigit() or int(pid) == os.getpid():
        continue
    fd_dir = f"/proc/{pid}/fd"
    try:
        for fd in os.listdir(fd_dir):
            try:
                target = os.readlink(f"{fd_dir}/{fd}")
            except OSError:
                continue
            if target.startswith("socket:[") and target[8:-1] in inodes:
                victims.add(int(pid))
                break
    except OSError:
        continue

for pid in victims:
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
if victims:
    time.sleep(0.3)
for pid in victims:
    try:
        os.kill(pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
PY
}

cleanup_ports
SERVICE_PID=""
cleanup() {
    if [ -n "$SERVICE_PID" ]; then
        kill -TERM -- "-$SERVICE_PID" 2>/dev/null || kill -TERM "$SERVICE_PID" 2>/dev/null || true
        sleep 0.2
        kill -KILL -- "-$SERVICE_PID" 2>/dev/null || kill -KILL "$SERVICE_PID" 2>/dev/null || true
    fi
    cleanup_ports
}
trap cleanup EXIT

if [ -f /home/user/serve_docs.py ] && [ ! -L /home/user/serve_docs.py ]; then
    setsid python3 /home/user/serve_docs.py >/tmp/serve_docs_verifier.log 2>&1 &
    SERVICE_PID=$!
    sleep 1
fi

cat <<'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import py_compile
import secrets
import socket
from urllib.parse import quote

import pytest
import requests

DOCS_DIR = "/home/user/organized_docs"
SCRIPT = "/home/user/serve_docs.py"
EXPECTED_COUNT = 25
SECRET_CODENAME = "VANGUARD"
EXPECTED_DOCS = {
    f"file{i}.txt": f"This is file {i}\n".encode("utf-8")
    for i in range(1, 26)
}


def recv_line(sock):
    data = bytearray()
    while not data.endswith(b"\n"):
        chunk = sock.recv(1)
        if not chunk:
            break
        data.extend(chunk)
    return bytes(data)


def authenticated_count():
    with socket.create_connection(("127.0.0.1", 9090), timeout=2) as s:
        s.settimeout(2)
        s.sendall(f"AUTH {SECRET_CODENAME}\n".encode("utf-8"))
        auth_response = recv_line(s).decode("utf-8")
        assert auth_response == "OK\n", (
            f"Expected 'OK\\n' for valid auth, got {auth_response!r}"
        )
        s.sendall(b"COUNT\n")
        return recv_line(s).decode("utf-8")


def test_service_script_exists_and_is_python():
    assert os.path.isfile(SCRIPT), f"Required service script {SCRIPT} does not exist."
    assert not os.path.islink(SCRIPT), f"{SCRIPT} must be a regular script, not a symlink."
    assert os.path.getsize(SCRIPT) > 0, f"{SCRIPT} is empty."
    py_compile.compile(SCRIPT, doraise=True)


def test_organized_docs_count_and_contents():
    assert os.path.isdir(DOCS_DIR), f"Directory {DOCS_DIR} does not exist."
    txt_files = glob.glob(os.path.join(DOCS_DIR, "*.txt"))
    assert len(txt_files) == EXPECTED_COUNT, (
        f"Expected {EXPECTED_COUNT} .txt files in {DOCS_DIR}, but found {len(txt_files)}."
    )

    actual_names = {os.path.basename(path) for path in txt_files}
    assert actual_names == set(EXPECTED_DOCS), "Extracted .txt filenames are incorrect."
    for name, expected in EXPECTED_DOCS.items():
        with open(os.path.join(DOCS_DIR, name), "rb") as f:
            assert f.read() == expected, f"Extracted content of {name} is incorrect."

    recursive = glob.glob(os.path.join(DOCS_DIR, "**", "*.txt"), recursive=True)
    assert len(recursive) == EXPECTED_COUNT, "All .txt files must be in the flat top level."


def test_http_server_serves_extracted_files():
    for name, expected in EXPECTED_DOCS.items():
        url = "http://127.0.0.1:8080/" + quote(name)
        try:
            response = requests.get(url, timeout=2)
        except requests.exceptions.RequestException as e:
            pytest.fail(f"Failed to connect to HTTP server at {url}: {e}")
        assert response.status_code == 200, (
            f"Expected HTTP 200 for {name}, got {response.status_code}."
        )
        assert response.content == expected, f"HTTP returned incorrect content for {name}."

    response = requests.get("http://127.0.0.1:8080/file1.txt", timeout=2)
    assert response.status_code == 200
    assert len(response.text) > 0


def test_tcp_server_valid_auth_and_count():
    try:
        count_response = authenticated_count()
    except ConnectionRefusedError:
        pytest.fail("Connection to TCP server at 127.0.0.1:9090 was refused.")
    except socket.timeout:
        pytest.fail("TCP server at 127.0.0.1:9090 timed out.")
    expected = f"FILES: {EXPECTED_COUNT}\n"
    assert count_response == expected, f"Expected {expected!r}, got {count_response!r}"


def test_tcp_count_is_computed_from_current_directory():
    probe_name = f"verifier_probe_{secrets.token_hex(8)}.txt"
    probe_path = os.path.join(DOCS_DIR, probe_name)
    try:
        with open(probe_path, "wb") as f:
            f.write(b"temporary verifier probe\n")
        response = authenticated_count()
        assert response == f"FILES: {EXPECTED_COUNT + 1}\n", (
            "COUNT must report the current number of .txt files rather than a fixed value."
        )
    finally:
        try:
            os.unlink(probe_path)
        except FileNotFoundError:
            pass
    assert authenticated_count() == f"FILES: {EXPECTED_COUNT}\n"


def test_tcp_server_invalid_auth():
    bad_codename = "INVALID_" + secrets.token_hex(8).upper()
    try:
        with socket.create_connection(("127.0.0.1", 9090), timeout=2) as s:
            s.settimeout(2)
            s.sendall(f"AUTH {bad_codename}\n".encode("utf-8"))
            auth_response = recv_line(s).decode("utf-8")
            assert auth_response == "ERROR\n", (
                f"Expected 'ERROR\\n' for invalid auth, got {auth_response!r}"
            )
            try:
                extra_data = s.recv(1024)
                assert extra_data == b"", "Expected connection to close after invalid auth."
            except socket.timeout:
                pytest.fail("Expected connection to close, but timed out waiting for EOF.")
    except ConnectionRefusedError:
        pytest.fail("Connection to TCP server at 127.0.0.1:9090 was refused.")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
