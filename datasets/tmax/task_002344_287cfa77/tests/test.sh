#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import random
import string
import json
import ssl
import socket
import threading
import time
import secrets
import re
import http.client
from http.server import BaseHTTPRequestHandler, HTTPServer
import pytest


def test_nginx_proxy():
    """Verify TLS configuration and that /health is actually proxied to port 5000."""
    cert_path = "/home/user/cert.pem"
    key_path = "/home/user/key.pem"
    conf_path = "/home/user/nginx.conf"

    assert os.path.isfile(cert_path), f"Certificate missing at {cert_path}"
    assert os.path.isfile(key_path), f"Private key missing at {key_path}"

    config_check = subprocess.run(
        ["nginx", "-T", "-c", conf_path], capture_output=True, text=True
    )
    assert config_check.returncode == 0, config_check.stderr
    effective_config = config_check.stdout + config_check.stderr
    assert re.search(r'(?m)^\s*ssl_certificate\s+["\']?/home/user/cert\.pem["\']?\s*;', effective_config), \
        "Nginx does not use /home/user/cert.pem"
    assert re.search(r'(?m)^\s*ssl_certificate_key\s+["\']?/home/user/key\.pem["\']?\s*;', effective_config), \
        "Nginx does not use /home/user/key.pem"

    cert_pub = subprocess.run(
        ["openssl", "x509", "-in", cert_path, "-pubkey", "-noout"],
        capture_output=True, check=True
    ).stdout.strip()
    key_pub = subprocess.run(
        ["openssl", "pkey", "-in", key_path, "-pubout"],
        capture_output=True, check=True
    ).stdout.strip()
    assert cert_pub == key_pub, "The private key does not match the certificate"

    identity = subprocess.run(
        ["openssl", "x509", "-in", cert_path, "-noout", "-subject", "-issuer", "-nameopt", "RFC2253"],
        capture_output=True, text=True, check=True
    ).stdout.strip().splitlines()
    assert len(identity) == 2
    assert identity[0].split("=", 1)[1] == identity[1].split("=", 1)[1], \
        "Certificate is not self-signed"

    trusted_ctx = ssl.create_default_context(cafile=cert_path)
    with socket.create_connection(("127.0.0.1", 8443), timeout=5) as raw:
        with trusted_ctx.wrap_socket(raw, server_hostname="localhost") as tls_sock:
            presented_der = tls_sock.getpeercert(binary_form=True)

    file_der = subprocess.run(
        ["openssl", "x509", "-in", cert_path, "-outform", "DER"],
        capture_output=True, check=True
    ).stdout
    assert presented_der == file_der, "Nginx is not presenting /home/user/cert.pem"

    subprocess.run(["pkill", "-f", "/home/user/backend.py"], check=False)
    time.sleep(0.5)

    token = "proxied-" + secrets.token_hex(24) + "\n"

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path.split("?", 1)[0] != "/health":
                self.send_response(404)
                self.end_headers()
                return
            body = token.encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *_args):
            pass

    backend = None
    for _ in range(20):
        try:
            backend = HTTPServer(("127.0.0.1", 5000), Handler)
            break
        except OSError:
            time.sleep(0.1)
    assert backend is not None, "Could not start verification backend on port 5000"

    thread = threading.Thread(target=backend.serve_forever, daemon=True)
    thread.start()
    try:
        conn = http.client.HTTPSConnection("localhost", 8443, context=trusted_ctx, timeout=5)
        conn.request("GET", "/health?nonce=" + secrets.token_hex(8))
        response = conn.getresponse()
        body = response.read().decode("utf-8", errors="replace")
        assert response.status == 200, f"Expected HTTP 200 OK, got {response.status}"
        assert body == token, f"Nginx did not return the dynamic backend response: {body!r}"
        conn.close()
    finally:
        backend.shutdown()
        backend.server_close()
        thread.join(timeout=2)


def test_parse_metrics_fuzz():
    """Fuzz test the parse_metrics script against an oracle implementation."""
    agent_script = "/home/user/parse_metrics"

    assert os.path.isfile(agent_script), f"Agent script missing at {agent_script}"
    assert os.access(agent_script, os.X_OK), f"Agent script at {agent_script} is not executable"

    random.seed(42)

    for _ in range(100):
        num_pairs = random.randint(1, 10)
        pairs = []
        expected_data = {}
        for _ in range(num_pairs):
            k_len = random.randint(3, 8)
            v_len = random.randint(1, 10)
            k = ''.join(random.choices(string.ascii_lowercase, k=k_len))
            v = ''.join(random.choices(string.ascii_letters + string.digits, k=v_len))

            ws1 = ' ' * random.randint(0, 3)
            ws2 = ' ' * random.randint(0, 3)
            ws3 = ' ' * random.randint(0, 3)
            ws4 = ' ' * random.randint(0, 3)

            pair_str = f"{ws1}{k}{ws2}:{ws3}{v}{ws4}"
            pairs.append(pair_str)
            expected_data[k] = v

        input_str = ""
        for i, p in enumerate(pairs):
            if i > 0:
                input_str += "," + (' ' * random.randint(0, 3))
            input_str += p

        expected_json = json.dumps({"data": expected_data}, separators=(',', ':'), sort_keys=True)

        try:
            proc = subprocess.run(
                [agent_script],
                input=input_str.encode('utf-8'),
                capture_output=True,
                timeout=2
            )
        except subprocess.TimeoutExpired:
            pytest.fail(f"Agent script timed out on input: {input_str}")

        assert proc.returncode == 0, f"Agent script failed with return code {proc.returncode} on input: {input_str}\nStderr: {proc.stderr.decode('utf-8', errors='replace')}"

        agent_output = proc.stdout.decode('utf-8', errors='replace').strip()
        assert agent_output == expected_json, f"Mismatch on input: {input_str}\nExpected: {expected_json}\nGot: {agent_output}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
