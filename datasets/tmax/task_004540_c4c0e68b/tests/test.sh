#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import socket
import ssl
import string
import subprocess
import time
import pytest

HOST = "127.0.0.1"
PORT = 8443
FORBIDDEN_BODY = b"Malicious payload"


def raw_https(request):
    ctx = ssl._create_unverified_context()
    with socket.create_connection((HOST, PORT), timeout=5) as sock:
        with ctx.wrap_socket(sock, server_hostname="localhost") as tls:
            tls.settimeout(5)
            tls.sendall(request)
            data = b""
            while True:
                try:
                    chunk = tls.recv(4096)
                except socket.timeout:
                    break
                if not chunk:
                    break
                data += chunk
    head, sep, body = data.partition(b"\r\n\r\n")
    assert sep, f"Invalid HTTP response: {data!r}"
    status = int(head.split(b"\r\n", 1)[0].split()[1])
    return status, head, body


def make_request(method, target, headers=None, body=b""):
    headers = dict(headers or {})
    headers.setdefault("Host", "localhost")
    headers.setdefault("Connection", "close")
    if body:
        headers.setdefault("Content-Length", str(len(body)))
    lines = [f"{method} {target} HTTP/1.1"]
    lines.extend(f"{k}: {v}" for k, v in headers.items())
    return ("\r\n".join(lines) + "\r\n\r\n").encode("ascii") + body


def test_files_and_tls_configuration():
    assert os.path.isdir("/home/user/nginx_setup")
    for path in ["/home/user/nginx_setup/nginx.conf", "/home/user/nginx_setup/server.crt",
                 "/home/user/nginx_setup/server.key", "/home/user/proxy_server"]:
        assert os.path.isfile(path), f"Missing required file: {path}"
    assert os.access("/home/user/proxy_server", os.X_OK), "proxy_server is not executable"

    cert = subprocess.check_output([
        "openssl", "x509", "-in", "/home/user/nginx_setup/server.crt",
        "-noout", "-subject", "-text"
    ], text=True)
    assert "Public-Key: (2048 bit)" in cert, "Certificate does not use a 2048-bit key"
    subject = subprocess.check_output([
        "openssl", "x509", "-in", "/home/user/nginx_setup/server.crt",
        "-noout", "-subject", "-nameopt", "RFC2253"
    ], text=True)
    assert "CN=localhost" in subject, f"Certificate CN is not localhost: {subject}"
    subprocess.check_call([
        "openssl", "pkey", "-in", "/home/user/nginx_setup/server.key", "-noout", "-check"
    ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def test_normal_routing_and_dynamic_redaction():
    token = "".join(random.SystemRandom().choices(string.ascii_letters + string.digits, k=23))
    other = "marker" + "".join(random.SystemRandom().choices(string.ascii_lowercase, k=12))
    status, _, body = raw_https(make_request(
        "GET", "/dynamic-normal-" + other,
        {"Cookie": f"theme={other}; session_id={token}; mode=safe"}
    ))
    text = body.decode("utf-8", "replace")
    assert status == 200, f"Expected 200, got {status}: {text}"
    assert "session_id=REDACTED" in text, text
    assert token not in text, "Original session_id reached the backend"
    assert f"theme={other}" in text and "mode=safe" in text, text


@pytest.mark.parametrize("placement", ["target", "header"])
def test_exact_union_select_is_blocked_without_client_encoding(placement):
    marker = "".join(random.SystemRandom().choices(string.ascii_letters, k=14))
    if placement == "target":
        # Send the literal instructed substring on the wire; high-level clients encode spaces.
        req = make_request("GET", f"/search/{marker}?q=UNION SELECT {marker}")
    else:
        req = make_request("GET", "/headers-" + marker,
                           {"X-Audit-" + marker: "prefix UNION SELECT suffix"})
    status, _, body = raw_https(req)
    assert status == 403, f"Expected 403 for literal UNION SELECT, got {status}: {body!r}"
    assert body == FORBIDDEN_BODY, body


@pytest.mark.parametrize("method,location", [("GET", "header"), ("POST", "target")])
def test_exact_script_is_blocked_in_varied_requests(method, location):
    marker = "".join(random.SystemRandom().choices(string.ascii_lowercase, k=15))
    if location == "header":
        req = make_request(method, "/clean-" + marker,
                           {"User-Agent": f"agent-{marker}<script>payload"})
    else:
        req = make_request(method, f"/submit/<script>/{marker}", body=b"x=1")
    status, _, body = raw_https(req)
    assert status == 403, f"Expected 403 for literal <script>, got {status}: {body!r}"
    assert body == FORBIDDEN_BODY, body


def test_near_matches_are_not_blocked():
    marker = "".join(random.SystemRandom().choices(string.ascii_lowercase, k=16))
    req = make_request("GET", "/near-" + marker,
                       {"X-Near-One": "UNION  SELECT", "X-Near-Two": "<Script>"})
    status, _, body = raw_https(req)
    assert status == 200, f"Proxy overblocked non-exact substrings: {status} {body!r}"
TEST_EOF

# Give correctly started services a short opportunity to finish binding.
for _ in $(seq 1 20); do
  if timeout 1 bash -c 'echo >/dev/tcp/127.0.0.1/8443' 2>/dev/null; then break; fi
  sleep 0.25
done

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
