#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import json
import os
import secrets
import socket
import subprocess
import threading
import time

import pytest

SERVICE_DIR = "/home/user/jwt_service"
SERVER = os.path.join(SERVICE_DIR, "server")
SOURCE = os.path.join(SERVICE_DIR, "server.cpp")
KEY_FILE = os.path.join(SERVICE_DIR, "managed_authorized_keys")
SCANNER = "/home/user/vuln_scanner.sh"
EXPECTED_KEY = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPfakekeyhere admin@hack"


def listener_inodes(port):
    result = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9:
                        local = fields[1]
                        state = fields[3]
                        if int(local.rsplit(":", 1)[1], 16) == port and state == "0A":
                            result.add(fields[9])
        except FileNotFoundError:
            pass
    return result


def kill_listeners(port):
    inodes = listener_inodes(port)
    if not inodes:
        return
    for pid in os.listdir("/proc"):
        if not pid.isdigit() or int(pid) == os.getpid():
            continue
        fd_dir = f"/proc/{pid}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    try:
                        os.kill(int(pid), 15)
                    except (ProcessLookupError, PermissionError):
                        pass
                    break
        except (FileNotFoundError, PermissionError):
            pass
    deadline = time.time() + 2
    while listener_inodes(port) and time.time() < deadline:
        time.sleep(0.05)


def process_owns_listener(pid, port):
    inodes = listener_inodes(port)
    if not inodes:
        return False
    try:
        for fd in os.listdir(f"/proc/{pid}/fd"):
            try:
                target = os.readlink(f"/proc/{pid}/fd/{fd}")
            except OSError:
                continue
            if target.startswith("socket:[") and target[8:-1] in inodes:
                return True
    except FileNotFoundError:
        return False
    return False


@pytest.fixture(scope="session", autouse=True)
def build_and_start_submitted_server():
    assert os.path.isfile(SOURCE), f"{SOURCE} does not exist"
    assert os.path.isfile(os.path.join(SERVICE_DIR, "Makefile")), "Makefile does not exist"

    with open(os.path.join(SERVICE_DIR, "Makefile")) as f:
        makefile = f.read()
    assert "server.cpp" in makefile and "g++" in makefile, "Makefile no longer builds server.cpp with g++"

    build = subprocess.run(
        ["make", "-B", "server"], cwd=SERVICE_DIR,
        capture_output=True, text=True, timeout=30
    )
    assert build.returncode == 0, f"Rebuilding server.cpp failed:\n{build.stdout}\n{build.stderr}"
    assert os.path.isfile(SERVER), "The build did not produce the required server binary"
    assert os.access(SERVER, os.X_OK), "The rebuilt server is not executable"

    kill_listeners(8080)
    proc = subprocess.Popen(
        [SERVER], cwd=SERVICE_DIR,
        stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )
    deadline = time.time() + 5
    while time.time() < deadline:
        if proc.poll() is not None:
            pytest.fail("The rebuilt server exited before listening on port 8080")
        if process_owns_listener(proc.pid, 8080):
            break
        time.sleep(0.05)
    else:
        proc.terminate()
        pytest.fail("The rebuilt server binary did not listen on port 8080")

    # Intentionally leave the submitted rebuilt server running after verification.
    yield proc


def request_server(token=None):
    headers = [
        "POST / HTTP/1.1",
        "Host: localhost:8080",
        "Content-Length: 0",
        "Connection: close",
    ]
    if token is not None:
        headers.insert(2, "Authorization: Bearer " + token)
    request = "\r\n".join(headers) + "\r\n\r\n"
    with socket.create_connection(("127.0.0.1", 8080), timeout=3) as sock:
        sock.sendall(request.encode())
        chunks = []
        while True:
            data = sock.recv(4096)
            if not data:
                break
            chunks.append(data)
    return b"".join(chunks).decode("latin1", errors="replace")


def jwt_json_segment(segment):
    try:
        return json.loads(segment)
    except (json.JSONDecodeError, UnicodeDecodeError):
        padding = "=" * ((4 - len(segment) % 4) % 4)
        decoded = base64.urlsafe_b64decode((segment + padding).encode()).decode()
        return json.loads(decoded)


def assert_alg_none_token(token):
    parts = token.split(".")
    assert len(parts) >= 3, "Scanner did not send a three-part JWT"
    header = jwt_json_segment(parts[0])
    payload = jwt_json_segment(parts[1])
    assert isinstance(header.get("alg"), str) and header["alg"].lower() == "none", \
        "Scanner JWT does not use alg=none"
    assert isinstance(payload.get("ssh_key"), str) and payload["ssh_key"], \
        "Scanner JWT does not contain an arbitrary SSH key"
    assert payload.get("role") == "admin", "Scanner JWT would not exercise the vulnerable admin path"


def run_mock_scanner(status, fixed_port=None):
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(("127.0.0.1", fixed_port or 0))
    port = server.getsockname()[1]
    server.listen(1)
    captured = []
    errors = []

    def serve():
        try:
            conn, _ = server.accept()
            conn.settimeout(3)
            data = b""
            while b"\r\n\r\n" not in data:
                chunk = conn.recv(4096)
                if not chunk:
                    break
                data += chunk
            captured.append(data.decode("latin1", errors="replace"))
            reason = "OK" if status == 200 else "Unauthorized"
            conn.sendall(f"HTTP/1.1 {status} {reason}\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".encode())
            conn.close()
        except Exception as exc:
            errors.append(exc)
        finally:
            server.close()

    thread = threading.Thread(target=serve, daemon=True)
    thread.start()
    result = subprocess.run(
        [SCANNER, f"127.0.0.1:{port}"], capture_output=True, text=True, timeout=10
    )
    thread.join(timeout=4)
    assert not errors, f"Mock server failed: {errors}"
    assert captured, "Scanner did not connect to the requested target"
    request = captured[0]
    first_line = request.split("\r\n", 1)[0]
    assert first_line.startswith("POST "), "Scanner did not construct an HTTP POST request"
    auth_lines = [line for line in request.split("\r\n") if line.lower().startswith("authorization: bearer ")]
    assert auth_lines, "Scanner did not send an Authorization: Bearer header"
    token = auth_lines[0].split(" ", 2)[2]
    assert_alg_none_token(token)
    return result


def test_ssh_key_injected():
    assert os.path.isfile(KEY_FILE), f"{KEY_FILE} does not exist."
    with open(KEY_FILE, "r") as f:
        content = f.read()
    assert EXPECTED_KEY in content, "The expected SSH key was not injected into managed_authorized_keys."


def test_exploit_token_saved_and_would_exploit_original_parser():
    token_file = "/home/user/exploit_token.txt"
    assert os.path.isfile(token_file), f"{token_file} does not exist."
    with open(token_file, "r") as f:
        token = f.read().strip()

    parts = token.split('.')
    assert len(parts) >= 3, "The exploit token does not look like a valid JWT (missing dots)."

    # Independently reproduce the vulnerable source's literal checks and extraction.
    dot1 = token.find('.')
    dot2 = token.find('.', dot1 + 1)
    header = token[:dot1]
    payload = token[dot1 + 1:dot2]
    assert ('"alg":"none"' in header or '"alg": "none"' in header), \
        "The saved token would not trigger the original alg=none bypass"
    assert ('"role":"admin"' in payload or '"role": "admin"' in payload), \
        "The saved token would not enter the original admin path"
    marker = '"ssh_key":"'
    key_pos = payload.find(marker)
    assert key_pos >= 0, "The saved token would not provide an SSH key to the original parser"
    key_start = key_pos + len(marker)
    key_end = payload.find('"', key_start)
    assert key_end >= 0 and payload[key_start:key_end] == EXPECTED_KEY, \
        "The saved token does not inject the required SSH key"


def test_scanner_exists_and_executable():
    assert os.path.isfile(SCANNER), f"{SCANNER} does not exist."
    assert os.access(SCANNER, os.X_OK), f"{SCANNER} is not executable."


def test_patched_server_rejects_none_case_insensitively_and_empty_alg():
    probe_key = "ssh-ed25519 " + secrets.token_hex(20) + " verifier@probe"
    payload = json.dumps({"role": "admin", "ssh_key": probe_key}, separators=(",", ":"))
    algorithms = ["none", "NONE", "NoNe", "nOnE", ""]
    for alg in algorithms:
        header = json.dumps({"alg": alg}, separators=(",", ":"))
        response = request_server(f"{header}.{payload}.")
        assert response.startswith("HTTP/1.1 401"), f"Server did not reject alg={alg!r} with HTTP 401: {response!r}"

    assert request_server("malformed-token").startswith("HTTP/1.1 401"), \
        "Server did not return 401 for a malformed unauthenticated token"
    assert request_server(None).startswith("HTTP/1.1 401"), \
        "Server did not return 401 when authentication was absent"
    with open(KEY_FILE) as f:
        assert probe_key not in f.read(), "A rejected alg=none probe still modified managed_authorized_keys"


def test_scanner_output_secure_on_patched_server():
    result = subprocess.run([SCANNER, "localhost:8080"], capture_output=True, text=True, timeout=10)
    assert "SECURE" in result.stdout.strip(), "Scanner did not output 'SECURE' for the patched server on port 8080."
    assert result.stdout.strip() == "SECURE", "Scanner must print exactly SECURE for a 401 response"


def test_scanner_output_vulnerable_on_original_server():
    kill_listeners(8081)
    result = run_mock_scanner(200, fixed_port=8081)
    assert "VULNERABLE" in result.stdout.strip(), "Scanner did not output 'VULNERABLE' for the vulnerable server on port 8081."
    assert result.stdout.strip() == "VULNERABLE", "Scanner must print exactly VULNERABLE for a 200 response"


def test_scanner_uses_response_status_on_unpredictable_targets():
    vulnerable = run_mock_scanner(200)
    secure = run_mock_scanner(401)
    assert vulnerable.stdout.strip() == "VULNERABLE"
    assert secure.stdout.strip() == "SECURE"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
