#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import contextlib
import os
import pathlib
import random
import re
import secrets
import signal
import socket
import string
import subprocess
import threading
import time

CHECKSUM_SCRIPT = "/home/user/compute_checksum.sh"
SERVER_SCRIPT = "/home/user/mock_server.sh"
CLIENT = "/home/user/api_client"


def checksum(payload):
    return (sum(ord(c) for c in payload) * len(payload)) % 256


def random_payload(min_len=1, max_len=32):
    alphabet = string.ascii_letters + string.digits
    return "".join(secrets.choice(alphabet) for _ in range(random.randint(min_len, max_len)))


@contextlib.contextmanager
def running_mock_server():
    proc = subprocess.Popen(
        [SERVER_SCRIPT],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        preexec_fn=os.setsid,
    )
    time.sleep(1)
    assert proc.poll() is None, "mock_server.sh exited before accepting requests"
    try:
        yield proc
    finally:
        if proc.poll() is None:
            os.killpg(os.getpgid(proc.pid), signal.SIGTERM)
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
                proc.wait(timeout=2)
        time.sleep(0.2)


def raw_http_request(payload):
    request = (
        f"GET /api/verify?payload={payload} HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n\r\n"
    ).encode("ascii")
    with socket.create_connection(("127.0.0.1", 8080), timeout=3) as sock:
        sock.settimeout(3)
        sock.sendall(request)
        sock.shutdown(socket.SHUT_WR)
        chunks = []
        while True:
            try:
                chunk = sock.recv(4096)
            except socket.timeout:
                raise AssertionError("mock server did not finish its HTTP response")
            if not chunk:
                break
            chunks.append(chunk)
    return b"".join(chunks)


def assert_http_checksum(response, expected):
    assert b"\r\n\r\n" in response, f"Invalid HTTP response: {response!r}"
    headers, body = response.split(b"\r\n\r\n", 1)
    assert headers.split(b"\r\n", 1)[0] == b"HTTP/1.1 200 OK", response
    assert body == f"CHECKSUM:{expected}".encode("ascii"), (
        f"Expected exact body CHECKSUM:{expected}, got {body!r}"
    )


def test_compute_checksum():
    assert os.path.isfile(CHECKSUM_SCRIPT), f"'{CHECKSUM_SCRIPT}' does not exist."
    assert os.access(CHECKSUM_SCRIPT, os.X_OK), f"'{CHECKSUM_SCRIPT}' is not executable."

    result = subprocess.run([CHECKSUM_SCRIPT, "abc"], capture_output=True, text=True)
    assert result.stdout.strip() == "114", (
        f"compute_checksum.sh returned '{result.stdout.strip()}', expected '114'."
    )

    payloads = ["A", "0", "hello", "Z9x1"] + [random_payload() for _ in range(12)]
    for payload in payloads:
        result = subprocess.run([CHECKSUM_SCRIPT, payload], capture_output=True, text=True, timeout=3)
        expected = str(checksum(payload))
        assert result.returncode == 0, f"checksum failed for {payload!r}: {result.stderr}"
        assert result.stderr == "", f"checksum wrote to stderr for {payload!r}: {result.stderr!r}"
        assert result.stdout in (expected, expected + "\n"), (
            f"checksum({payload!r}) produced {result.stdout!r}; expected only {expected!r}"
        )

    assert subprocess.run([CHECKSUM_SCRIPT], capture_output=True).returncode != 0
    assert subprocess.run([CHECKSUM_SCRIPT, "a", "b"], capture_output=True).returncode != 0


def test_makefile_and_compilation():
    makefile = "/home/user/Makefile"
    assert os.path.isfile(makefile), f"'{makefile}' does not exist."

    if os.path.exists(CLIENT):
        os.remove(CLIENT)
    result = subprocess.run(["make", "client"], cwd="/home/user", capture_output=True, text=True)
    assert result.returncode == 0, f"make client failed:\n{result.stderr}"
    assert os.path.isfile(CLIENT), "Makefile did not build '/home/user/api_client'."
    assert os.access(CLIENT, os.X_OK), "Built api_client is not executable."


def test_mock_server_general_and_sequential_requests():
    assert os.path.isfile(SERVER_SCRIPT), f"'{SERVER_SCRIPT}' does not exist."
    assert os.access(SERVER_SCRIPT, os.X_OK), f"'{SERVER_SCRIPT}' is not executable."

    payloads = ["test", "abc", "hello"] + [random_payload() for _ in range(10)]
    with running_mock_server():
        for payload in payloads:
            assert_http_checksum(raw_http_request(payload), checksum(payload))

        # Ensure the server actually delegates checksum calculation to the required script.
        path = pathlib.Path(CHECKSUM_SCRIPT)
        original = path.read_bytes()
        original_mode = path.stat().st_mode
        marker = random.randint(1, 255)
        try:
            path.write_text(f"#!/bin/bash\nprintf '%s' '{marker}'\n")
            os.chmod(path, 0o755)
            assert_http_checksum(raw_http_request(random_payload()), marker)
        finally:
            path.write_bytes(original)
            os.chmod(path, original_mode)


def test_client_sends_request_and_prints_actual_response_body():
    assert os.path.isfile(CLIENT), f"'{CLIENT}' not found."
    payload = random_payload()
    response_body = "SERVER_TOKEN_" + secrets.token_hex(12)
    captured = []
    errors = []

    listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    listener.bind(("127.0.0.1", 8080))
    listener.listen(1)

    def serve_once():
        try:
            conn, _ = listener.accept()
            with conn:
                conn.settimeout(3)
                data = b""
                while b"\r\n\r\n" not in data:
                    chunk = conn.recv(4096)
                    if not chunk:
                        break
                    data += chunk
                captured.append(data)
                body = response_body.encode("ascii")
                conn.sendall(
                    b"HTTP/1.1 200 OK\r\n"
                    + f"Content-Length: {len(body)}\r\nConnection: close\r\n\r\n".encode("ascii")
                    + body
                )
        except Exception as exc:
            errors.append(exc)
        finally:
            listener.close()

    thread = threading.Thread(target=serve_once, daemon=True)
    thread.start()
    result = subprocess.run([CLIENT, payload], capture_output=True, text=True, timeout=5)
    thread.join(timeout=4)

    assert not thread.is_alive(), "client did not complete its request"
    assert not errors, f"controlled HTTP server failed: {errors}"
    assert result.returncode == 0, result.stderr
    assert captured, "client did not connect to localhost:8080"
    request_line = captured[0].split(b"\r\n", 1)[0]
    assert request_line == f"GET /api/verify?payload={payload} HTTP/1.1".encode("ascii"), request_line
    assert result.stdout.strip() == response_body, (
        f"client did not print the server's actual response body: {result.stdout!r}"
    )


def test_mock_server_integration_and_memory_leak():
    assert os.path.isfile(CLIENT), f"'{CLIENT}' not found."
    with running_mock_server():
        fixed = subprocess.run([CLIENT, "test"], capture_output=True, text=True, timeout=5)
        assert "CHECKSUM:0" in fixed.stdout, (
            f"Client output does not contain 'CHECKSUM:0'. Got:\n{fixed.stdout}"
        )

        result = subprocess.run(
            ["valgrind", "--leak-check=full", "--error-exitcode=97", CLIENT, "verify"],
            capture_output=True,
            text=True,
            timeout=15,
        )
        assert result.returncode == 0, f"valgrind/client failed:\n{result.stderr}\n{result.stdout}"
        assert "CHECKSUM:126" in result.stdout, result.stdout
        assert "definitely lost: 0 bytes" in result.stderr, "api_client.c still has a memory leak."
        assert re.search(r"ERROR SUMMARY: 0 errors", result.stderr), result.stderr


def test_valgrind_report():
    report = "/home/user/valgrind_report.txt"
    assert os.path.isfile(report), f"'{report}' does not exist."
    content = pathlib.Path(report).read_text(errors="replace")

    assert "definitely lost: 0 bytes" in content, (
        "valgrind_report.txt does not show 'definitely lost: 0 bytes'."
    )
    assert "HEAP SUMMARY:" in content, "valgrind_report.txt is missing the Valgrind heap summary."
    assert re.search(r"ERROR SUMMARY: 0 errors", content), "valgrind_report.txt reports errors."
    assert re.search(r"Command:.*api_client(?:\s+|\s+\./)?hello(?:\s|$)", content), (
        "valgrind_report.txt was not produced for api_client with payload 'hello'."
    )
    assert "CHECKSUM:100" in content, (
        "valgrind_report.txt does not include the expected live response for payload 'hello'."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
