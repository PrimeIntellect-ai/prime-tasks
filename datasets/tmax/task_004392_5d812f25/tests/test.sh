#!/bin/bash
set -e
mkdir -p /logs/verifier

# Stop the mock server started by the agent so behavioral tests can control port 8443.
pkill -f '^python(3)? /home/user/server/server.py( |$)' 2>/dev/null || true
sleep 1

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import json
import os
import secrets
import ssl
import subprocess
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer

import pytest

CLIENT = "/home/user/vulnerable_client.py"
REPORT = "/home/user/audit_report.json"


class ReusableHTTPServer(HTTPServer):
    allow_reuse_address = True


def test_vulnerable_client_remediated():
    path = CLIENT
    assert os.path.isfile(path), f"File {path} is missing."
    with open(path, "r") as f:
        content = f.read()

    # Check for removal of --token
    assert "--token" not in content, "The vulnerable client still contains the '--token' argument."

    # Check for usage of SECRET_TOKEN
    assert "SECRET_TOKEN" in content, "The client does not appear to use the 'SECRET_TOKEN' environment variable."

    # Check for certificate validation
    assert "verify=False" not in content, "The client still contains 'verify=False'."
    assert "/home/user/certs/root_ca.pem" in content, "The client does not reference the root CA path for validation."


def test_audit_report_content():
    path = REPORT
    assert os.path.isfile(path), f"Audit report {path} was not created."

    with open(path, "r") as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {path} is not valid JSON.")

    assert report.get("token_env_var_used") == "SECRET_TOKEN", "Incorrect or missing 'token_env_var_used'."
    assert report.get("ca_cert_path") == "/home/user/certs/root_ca.pem", "Incorrect or missing 'ca_cert_path'."
    assert report.get("decoded_payload") == "Compliance_Audit_Success_Data_9921", "Incorrect or missing 'decoded_payload'."

    insecure_cookies = report.get("insecure_cookies")
    assert isinstance(insecure_cookies, list), "'insecure_cookies' must be a list."
    assert "legacy_session" in insecure_cookies, "'legacy_session' missing from 'insecure_cookies'."


def run_https_server(certfile, keyfile, token, payload, cookie_headers):
    state = {"authorization": None, "requests": 0}

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            state["requests"] += 1
            state["authorization"] = self.headers.get("Authorization")
            body = json.dumps({"payload": base64.b64encode(payload.encode("utf-8")).decode("ascii")}).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            for cookie in cookie_headers:
                self.send_header("Set-Cookie", cookie)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *args):
            pass

    server = ReusableHTTPServer(("127.0.0.1", 8443), Handler)
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(certfile=certfile, keyfile=keyfile)
    server.socket = context.wrap_socket(server.socket, server_side=True)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    return server, thread, state


def run_client(token):
    env = os.environ.copy()
    env["SECRET_TOKEN"] = token
    # Do not allow ambient CA-related variables to make the TLS checks pass.
    for name in ("REQUESTS_CA_BUNDLE", "CURL_CA_BUNDLE", "SSL_CERT_FILE"):
        env.pop(name, None)
    return subprocess.run(
        ["python3", CLIENT],
        cwd="/home/user",
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )


def stop_server(server, thread):
    server.shutdown()
    server.server_close()
    thread.join(timeout=5)


def test_client_executes_securely_and_derives_dynamic_report():
    token = "token_" + secrets.token_urlsafe(18)
    payload = "dynamic_audit_" + secrets.token_hex(16)
    insecure_plain = "plain_" + secrets.token_hex(5)
    insecure_no_http_only = "nohttp_" + secrets.token_hex(5)
    secure_cookie = "safe_" + secrets.token_hex(5)
    cookies = [
        f"{insecure_plain}=value1; Path=/",
        f"{insecure_no_http_only}=value2; Path=/; Secure",
        f"{secure_cookie}=value3; Path=/; Secure; HttpOnly",
    ]

    if os.path.exists(REPORT):
        os.remove(REPORT)

    server, thread, state = run_https_server(
        "/home/user/certs/server_chain.pem",
        "/home/user/certs/server.key",
        token,
        payload,
        cookies,
    )
    try:
        result = run_client(token)
    finally:
        stop_server(server, thread)

    assert result.returncode == 0, f"Client failed against the trusted server: {result.stderr}"
    assert state["requests"] >= 1, "The remediated client did not contact the HTTPS server."
    assert state["authorization"] == f"Bearer {token}", "The client did not read and send the dynamic SECRET_TOKEN value."
    assert os.path.isfile(REPORT), "Running the client did not create the audit report."

    with open(REPORT, "r", encoding="utf-8") as f:
        report = json.load(f)

    assert set(report) == {"token_env_var_used", "ca_cert_path", "decoded_payload", "insecure_cookies"}
    assert report["token_env_var_used"] == "SECRET_TOKEN"
    assert report["ca_cert_path"] == "/home/user/certs/root_ca.pem"
    assert report["decoded_payload"] == payload, "The client did not decode the server's dynamic Base64 payload."
    assert isinstance(report["insecure_cookies"], list)
    assert set(report["insecure_cookies"]) == {insecure_plain, insecure_no_http_only}, \
        "The client did not correctly distinguish insecure cookies from a Secure, HttpOnly cookie."


def test_client_rejects_untrusted_certificate(tmp_path):
    cert = tmp_path / "untrusted.crt"
    key = tmp_path / "untrusted.key"
    subprocess.run(
        [
            "openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes",
            "-days", "2", "-sha256", "-subj", "/CN=127.0.0.1",
            "-addext", "subjectAltName=IP:127.0.0.1",
            "-keyout", str(key), "-out", str(cert),
        ],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )

    if os.path.exists(REPORT):
        os.remove(REPORT)

    token = "reject_" + secrets.token_urlsafe(16)
    server, thread, state = run_https_server(
        str(cert), str(key), token, "must_not_be_accepted", ["badcookie=x; Path=/"]
    )
    try:
        run_client(token)
    finally:
        stop_server(server, thread)

    assert state["requests"] == 0, "The client sent an HTTP request despite the untrusted certificate."
    assert not os.path.exists(REPORT), "The client generated a successful report from an untrusted TLS connection."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
