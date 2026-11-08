#!/bin/bash
set -e
mkdir -p /logs/verifier

# Put the supplied services into a known running state before verification.
redis-cli ping >/dev/null 2>&1 || redis-server --daemonize yes
for _ in $(seq 1 30); do
    redis-cli ping >/dev/null 2>&1 && break
    sleep 0.1
done

pkill -9 -f '^/app/go-api/api$' >/dev/null 2>&1 || true
pkill -9 nginx >/dev/null 2>&1 || true
/app/go-api/api >/tmp/verifier-api.log 2>&1 &
echo $! >/tmp/verifier-api.pid

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import signal
import socket
import ssl
import string
import subprocess
import tempfile
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, HTTPServer

import pytest


def wait_port(port, open_expected=True, timeout=5):
    deadline = time.time() + timeout
    while time.time() < deadline:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
            is_open = sock.connect_ex(("127.0.0.1", port)) == 0
        if is_open == open_expected:
            return
        time.sleep(0.05)
    raise AssertionError(f"port {port} did not reach expected state open={open_expected}")


def start_or_reload_nginx():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        listening = sock.connect_ex(("127.0.0.1", 8080)) == 0
    if listening:
        result = subprocess.run(
            ["nginx", "-s", "reload", "-c", "/app/nginx/nginx.conf"],
            capture_output=True,
            text=True,
        )
    else:
        result = subprocess.run(
            ["nginx", "-c", "/app/nginx/nginx.conf"],
            capture_output=True,
            text=True,
        )
    assert result.returncode == 0, result.stderr
    wait_port(8080)
    time.sleep(0.2)


def fetch(path, timeout=3):
    return urllib.request.urlopen("http://127.0.0.1:8080" + path, timeout=timeout)


def test_redis_and_nginx_proxy():
    assert subprocess.run(["redis-cli", "ping"], capture_output=True, text=True).stdout.strip() == "PONG"
    wait_port(8443)

    checked = subprocess.run(
        ["nginx", "-t", "-c", "/app/nginx/nginx.conf"],
        capture_output=True,
        text=True,
    )
    assert checked.returncode == 0, checked.stderr

    dumped = subprocess.run(
        ["nginx", "-T", "-c", "/app/nginx/nginx.conf"],
        capture_output=True,
        text=True,
    )
    assert dumped.returncode == 0, dumped.stderr
    config = re.sub(r"#.*", "", dumped.stdout + dumped.stderr)
    assert re.search(r"\blisten\s+[^;]*\b8080\b[^;]*;", config)
    assert re.search(r"\bproxy_pass\s+https://127\.0\.0\.1:8443(?:/)?\s*;", config)
    assert re.search(r"\bproxy_ssl_certificate\s+/app/certs/client\.crt\s*;", config)
    assert re.search(r"\bproxy_ssl_certificate_key\s+/app/certs/client\.key\s*;", config)
    assert re.search(r"\bproxy_ssl_trusted_certificate\s+/app/certs/ca\.crt\s*;", config)
    assert re.search(r"\bproxy_ssl_verify\s+on\s*;", config)

    start_or_reload_nginx()

    # Preserve the original end-to-end assertion against the supplied API.
    try:
        with fetch("/ping") as response:
            data = json.loads(response.read().decode("utf-8"))
            assert data.get("status") == "ok", f"Expected status 'ok', got: {data}"
    except Exception as exc:
        pytest.fail(f"Failed to connect to Nginx proxy or invalid response: {exc}")

    # Replace the API with an unpredictable mTLS backend. A static Nginx return
    # cannot know either the path or response generated here.
    with open("/tmp/verifier-api.pid") as handle:
        api_pid = int(handle.read().strip())
    try:
        os.kill(api_pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    wait_port(8443, open_expected=False)

    nonce = "".join(random.SystemRandom().choices(string.ascii_letters + string.digits, k=28))
    path = "/verify-proxy/" + nonce
    expected = {"proxied": nonce, "method": "GET"}

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path == path:
                body = json.dumps(expected).encode()
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
            else:
                self.send_error(404)

        def log_message(self, *_args):
            pass

    def make_server(cert, key):
        server = HTTPServer(("127.0.0.1", 8443), Handler)
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(cert, key)
        context.load_verify_locations("/app/certs/ca.crt")
        context.verify_mode = ssl.CERT_REQUIRED
        server.socket = context.wrap_socket(server.socket, server_side=True)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        return server, thread

    server, thread = make_server("/app/certs/server.crt", "/app/certs/server.key")
    try:
        with fetch(path) as response:
            assert json.loads(response.read().decode()) == expected
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)

    # A backend certificate outside the configured CA must be rejected. The
    # backend still requires the valid client certificate, independently testing mTLS.
    with tempfile.TemporaryDirectory() as directory:
        bad_key = os.path.join(directory, "bad.key")
        bad_cert = os.path.join(directory, "bad.crt")
        made = subprocess.run(
            ["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes",
             "-days", "1", "-keyout", bad_key, "-out", bad_cert,
             "-subj", "/CN=127.0.0.1"],
            capture_output=True,
            text=True,
        )
        assert made.returncode == 0, made.stderr
        server, thread = make_server(bad_cert, bad_key)
        try:
            with pytest.raises(urllib.error.HTTPError) as caught:
                fetch(path)
            assert caught.value.code == 502
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=2)


def run_filter(input_text):
    assert os.path.isfile("/app/filter.go"), "/app/filter.go is missing"
    result = subprocess.run(
        ["go", "run", "/app/filter.go"],
        input=input_text,
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"Go script failed: {result.stderr}"
    return [line for line in result.stdout.splitlines() if line.strip()]


def test_filter_evil_corpus():
    evil_corpus = "/app/corpora/evil.jsonl"
    assert os.path.isfile(evil_corpus), f"Evil corpus missing at {evil_corpus}"
    with open(evil_corpus) as handle:
        output_lines = run_filter(handle.read())
    assert len(output_lines) == 0, f"{len(output_lines)} evil logs bypassed the filter"


def test_filter_clean_corpus():
    clean_corpus = "/app/corpora/clean.jsonl"
    assert os.path.isfile(clean_corpus), f"Clean corpus missing at {clean_corpus}"
    with open(clean_corpus) as handle:
        source = handle.read()
    input_lines = [line for line in source.splitlines() if line.strip()]
    output_lines = run_filter(source)
    assert len(output_lines) == len(input_lines)
    parsed = [json.loads(line) for line in output_lines]
    assert parsed[0]["request_payload"] == "hello"
    assert parsed[0]["response_body"] == "My secret is CRED-XXXX-XXXX"
    assert "CRED-A1B2-C3D4" not in output_lines[0]


def test_filter_generated_cases_and_json_handling():
    rng = random.SystemRandom()
    token = "".join(rng.choices(string.ascii_uppercase + string.digits, k=8))
    cred1 = f"CRED-{token[:4]}-{token[4:]}"
    token2 = "".join(rng.choices(string.ascii_uppercase + string.digits, k=8))
    cred2 = f"CRED-{token2[:4]}-{token2[4:]}"

    benign = [
        {"request_payload": urllib.parse.quote("ordinary ../ split".replace("../", ". ./"), safe=""),
         "response_body": f"before {cred1} middle {cred2} after", "id": 17},
        {"request_payload": urllib.parse.quote("select unionized values", safe=""),
         "response_body": "no credential", "nested": {"keep": True}},
        {"request_payload": "percent%20encoded%20benign", "response_body": "CRED-abcd-EFGH"},
    ]
    malicious_decoded = [
        "prefix../etc/passwd",
        "prefix..\\windows\\system.ini",
        "prefix UnIoN SeLeCt secret",
        "x OR 1=1 -- " + token,
    ]
    malicious = [
        {"request_payload": urllib.parse.quote(payload, safe=""),
         "response_body": f"must not survive {cred1}", "marker": token + str(i)}
        for i, payload in enumerate(malicious_decoded)
    ]
    # Exercise application/x-www-form-urlencoded plus decoding as well.
    malicious.append({"request_payload": "abc+uNiOn+SeLeCt+xyz", "response_body": "drop"})

    records = [benign[0], malicious[0], benign[1], malicious[1], malicious[2], benign[2], malicious[3], malicious[4]]
    lines = [json.dumps(record, separators=(",", ":")) for record in records]
    lines.insert(2, "not valid json " + token)
    lines.insert(6, '{"request_payload":')

    output_lines = run_filter("\n".join(lines) + "\n")
    assert len(output_lines) == len(benign), "clean lines must be preserved and malicious/invalid lines skipped"
    output = [json.loads(line) for line in output_lines]

    expected = []
    credential_pattern = re.compile(r"CRED-[A-Z0-9]{4}-[A-Z0-9]{4}")
    for record in benign:
        copy = dict(record)
        copy["response_body"] = credential_pattern.sub("CRED-XXXX-XXXX", copy["response_body"])
        expected.append(copy)
    assert output == expected
    serialized = "\n".join(output_lines)
    assert cred1 not in serialized and cred2 not in serialized
    for record in malicious:
        assert record.get("marker", token) not in serialized
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
