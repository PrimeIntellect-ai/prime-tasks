#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import socket
import string
import time
import pytest

HOST = "127.0.0.1"
PORT = 8443


def test_vuln_dir_txt():
    """Verify that the hardcoded upload directory was correctly extracted."""
    path = "/app/vuln_dir.txt"
    assert os.path.isfile(path), f"Missing required file: {path}"

    with open(path, "r") as f:
        content = f.read().strip()

    expected = "/var/www/internal_uploads/"
    assert content == expected, f"Expected '{expected}' in {path}, but found '{content}'"


def test_clean_logs_txt():
    """Verify that the compromised logs were properly redacted."""
    path = "/app/clean_logs.txt"
    assert os.path.isfile(path), f"Missing required file: {path}"

    with open(path, "r") as f:
        content = f.read()

    expected = """GET /admin HTTP/1.1
Host: internal.corp
Cookie: session_token=[REDACTED]
User-Agent: Mozilla/5.0

GET /upload HTTP/1.1
Host: internal.corp
Cookie: session_token=[REDACTED]
User-Agent: curl/7.68.0
"""
    assert content.strip() == expected.strip(), "The redacted logs do not match the expected output."


def send_raw_http_request(host, port, request_str):
    """Send an unnormalized raw HTTP request and collect the complete response."""
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(1.5)
        try:
            s.connect((host, port))
        except ConnectionRefusedError:
            pytest.fail(f"Could not connect to honeypot service at {host}:{port}. Is it running?")

        s.sendall(request_str.encode("utf-8"))
        response = b""
        try:
            while True:
                chunk = s.recv(4096)
                if not chunk:
                    break
                response += chunk
        except socket.timeout:
            pass

    return response.decode("utf-8", errors="replace")


def parse_http_response(response):
    """Parse one HTTP response and reject injected/contradictory status lines."""
    assert response, "The service returned an empty response"
    assert "\r\n\r\n" in response, f"Response lacks a valid HTTP header terminator:\n{response}"
    head, body = response.split("\r\n\r\n", 1)
    lines = head.split("\r\n")
    assert re.fullmatch(r"HTTP/1\.1 [0-9]{3} [^\r\n]+", lines[0]), \
        f"Invalid HTTP status line: {lines[0]!r}"

    status_lines = re.findall(r"(?m)^HTTP/[0-9]+\.[0-9]+ [0-9]{3}(?: [^\r\n]*)?$", response)
    assert len(status_lines) == 1, f"Response contains contradictory or extra status lines:\n{response}"

    headers = []
    for line in lines[1:]:
        assert ":" in line, f"Malformed HTTP header {line!r}"
        name, value = line.split(":", 1)
        assert name and value.strip(), f"Malformed HTTP header {line!r}"
        headers.append((name, value.strip()))

    incident_headers = [v for n, v in headers if n.lower() == "x-incident-response"]
    assert incident_headers == ["Active"], \
        f"Expected exactly one X-Incident-Response: Active header, got {incident_headers!r}"

    content_lengths = [v for n, v in headers if n.lower() == "content-length"]
    assert len(content_lengths) <= 1, "Response contains multiple Content-Length headers"
    if content_lengths:
        assert content_lengths[0].isdigit(), "Content-Length is not numeric"
        assert int(content_lengths[0]) == len(body.encode("utf-8")), \
            "Content-Length does not match the response body"

    return lines[0], headers, body


def assert_response(request, expected_status, expected_body=None, body_must_be_empty=False):
    response = send_raw_http_request(HOST, PORT, request)
    status, headers, body = parse_http_response(response)
    assert expected_status in response, f"Expected {expected_status}, got:\n{response}"
    assert status == expected_status, f"Expected only {expected_status}, got {status!r}"
    assert "X-Incident-Response: Active" in response, \
        f"Missing required header 'X-Incident-Response: Active' in response:\n{response}"
    if expected_body is not None:
        assert expected_body in response, "Response body does not contain the expected clean logs."
        assert body == expected_body, "The /logs body is not exactly /app/clean_logs.txt"
    if body_must_be_empty:
        assert body == "", f"403 Forbidden must have no body, got {body!r}"
    return response


def listening_socket_owners(port):
    """Return PIDs owning an IPv4 listening socket on the requested port."""
    inode = None
    wanted = f"{port:04X}"
    try:
        with open("/proc/net/tcp", "r") as f:
            for line in f.readlines()[1:]:
                fields = line.split()
                local_port = fields[1].split(":")[1].upper()
                if local_port == wanted and fields[3] == "0A":
                    inode = fields[9]
                    break
    except OSError:
        return []
    if inode is None:
        return []

    owners = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    if os.readlink(f"{fd_dir}/{fd}") == f"socket:[{inode}]":
                        owners.append(int(entry))
                        break
                except OSError:
                    continue
        except OSError:
            continue
    return owners


def proc_info(pid):
    try:
        exe = os.path.basename(os.readlink(f"/proc/{pid}/exe"))
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            cmd = f.read().replace(b"\0", b" ").decode("utf-8", "replace")
        with open(f"/proc/{pid}/stat", "r") as f:
            ppid = int(f.read().split()[3])
        return exe, cmd, ppid
    except (OSError, ValueError, IndexError):
        return "", "", 0


def is_bash_based_listener(pid):
    exe, cmd, parent = proc_info(pid)
    if exe not in {"bash", "nc", "netcat", "socat"}:
        return False
    if exe == "bash" or re.search(r"(^|[ /])bash([ /]|$)", cmd) or re.search(r"\.sh(?:[ '\"]|$)", cmd):
        return True
    for _ in range(6):
        if parent <= 1:
            break
        pexe, pcmd, parent = proc_info(parent)
        if pexe == "bash" or re.search(r"(^|[ /])bash([ /]|$)", pcmd):
            return True
    return False


def test_service_is_bash_based():
    owners = []
    for _ in range(20):
        owners = listening_socket_owners(PORT)
        if owners:
            break
        time.sleep(0.1)
    assert owners, f"No process owns a listening socket on {HOST}:{PORT}"
    assert any(is_bash_based_listener(pid) for pid in owners), \
        "The listener is not implemented by Bash with nc/socat as required"


def test_honeypot_logs_endpoint():
    """Verify the honeypot responds to GET /logs with exactly the clean logs."""
    request = "GET /logs HTTP/1.1\r\nHost: 127.0.0.1:8443\r\n\r\n"
    with open("/app/clean_logs.txt", "r") as f:
        expected_body = f.read()
    assert_response(request, "HTTP/1.1 200 OK", expected_body=expected_body)


def test_honeypot_path_traversal():
    """Verify the honeypot blocks path traversal attempts with an empty body."""
    request = "GET /logs/../../etc/passwd HTTP/1.1\r\nHost: 127.0.0.1:8443\r\n\r\n"
    assert_response(request, "HTTP/1.1 403 Forbidden", body_must_be_empty=True)


def test_honeypot_not_found():
    """Verify the honeypot returns only 404 for unknown paths."""
    request = "GET /random HTTP/1.1\r\nHost: 127.0.0.1:8443\r\n\r\n"
    assert_response(request, "HTTP/1.1 404 Not Found")


def test_randomized_routing_and_traversal():
    """Exercise derived paths so a fixed, constant response cannot pass."""
    token = "".join(random.SystemRandom().choice(string.ascii_letters + string.digits) for _ in range(18))
    unknown_paths = [
        f"/{token}",
        f"/logs?probe={token}",
        f"/{token}/logs",
    ]
    for path in unknown_paths:
        request = f"GET {path} HTTP/1.1\r\nHost: {HOST}:{PORT}\r\nX-Probe: {token}\r\n\r\n"
        assert_response(request, "HTTP/1.1 404 Not Found")

    traversal_paths = [
        f"/{token}/../secret",
        f"/prefix..{token}/file",
        f"/../../{token}",
    ]
    for path in traversal_paths:
        request = f"GET {path} HTTP/1.1\r\nHost: {HOST}:{PORT}\r\nX-Probe: {token}\r\n\r\n"
        assert_response(request, "HTTP/1.1 403 Forbidden", body_must_be_empty=True)

    # The instruction requires an exact HTTP/1.1 request line for the logs route.
    request = f"GET /logs HTTP/1.0\r\nHost: {HOST}:{PORT}\r\nX-Probe: {token}\r\n\r\n"
    assert_response(request, "HTTP/1.1 404 Not Found")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
