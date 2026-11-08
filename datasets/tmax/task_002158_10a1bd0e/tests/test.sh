#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import time
import json
import base64
import hashlib
import secrets
import string
import subprocess
import urllib.request
import urllib.parse
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer
import pytest


def sign(payload: str) -> str:
    reversed_str = payload[::-1]
    xored_bytes = bytes([ord(c) ^ 0x3F for c in reversed_str])
    return base64.b64encode(xored_bytes).decode('utf-8')


class DummyBackendHandler(BaseHTTPRequestHandler):
    records = []
    proof_key = os.urandom(32)
    serial = 0

    def log_message(self, format, *args):
        pass

    def do_GET(self):
        type(self).serial += 1
        signature = self.headers.get('X-Custom-Signature')
        proof_input = f"{type(self).serial}\0{self.path}\0{signature}".encode('utf-8')
        proof = hashlib.blake2s(
            proof_input, key=type(self).proof_key, digest_size=16
        ).hexdigest()
        type(self).records.append((self.path, signature, proof))

        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        headers_dict = {
            f"HTTP_{k.upper().replace('-', '_')}": v
            for k, v in self.headers.items()
        }
        headers_dict['__backend_proof'] = proof
        self.wfile.write(json.dumps(headers_dict).encode('utf-8'))


@pytest.fixture(scope="module")
def dummy_backend():
    DummyBackendHandler.records = []
    DummyBackendHandler.serial = 0
    DummyBackendHandler.proof_key = os.urandom(32)
    server = HTTPServer(('127.0.0.1', 9000), DummyBackendHandler)
    thread = threading.Thread(target=server.serve_forever)
    thread.daemon = True
    thread.start()
    yield DummyBackendHandler
    server.shutdown()
    server.server_close()


@pytest.fixture(scope="module")
def user_proxy():
    proxy_script = "/home/user/proxy.py"
    assert os.path.exists(proxy_script), f"Proxy script not found at {proxy_script}"

    p = subprocess.Popen(["python3", proxy_script])

    started = False
    for _ in range(20):
        try:
            urllib.request.urlopen("http://127.0.0.1:8080/", timeout=0.1)
            started = True
            break
        except Exception:
            time.sleep(0.1)

    yield p
    p.terminate()
    p.wait()


def test_proxy_accuracy_and_performance(dummy_backend, user_proxy):
    success = 0
    total_requests = 2000

    start_time = time.time()
    for i in range(total_requests):
        uri = f"/api/test?id={i}"
        try:
            req = urllib.request.Request(f"http://127.0.0.1:8080{uri}")
            with urllib.request.urlopen(req, timeout=1.0) as response:
                data = json.loads(response.read().decode('utf-8'))
                sig = data.get("HTTP_X_CUSTOM_SIGNATURE")

                expected = sign(uri)
                if sig == expected:
                    success += 1
        except Exception:
            pass

    end_time = time.time()
    time_taken = end_time - start_time
    accuracy = success / total_requests

    assert accuracy == 1.0, f"Accuracy is {accuracy}, expected 1.0 (some signatures mismatched or requests failed)"
    assert time_taken <= 1.5, f"Performance threshold failed: time taken {time_taken:.3f}s > 1.5s"

    observed = {(path, signature) for path, signature, _ in dummy_backend.records}
    for i in range(total_requests):
        uri = f"/api/test?id={i}"
        assert (uri, sign(uri)) in observed, f"Backend did not receive correctly signed request {uri}"


def test_unpredictable_uris_are_signed_and_forwarded(dummy_backend, user_proxy):
    alphabet = string.ascii_letters + string.digits

    for _ in range(80):
        path_a = ''.join(secrets.choice(alphabet) for _ in range(10))
        path_b = ''.join(secrets.choice(alphabet) for _ in range(17))
        key = ''.join(secrets.choice(string.ascii_lowercase) for _ in range(7))
        raw_value = ''.join(secrets.choice(alphabet) for _ in range(13)) + " /?&=+"
        value = urllib.parse.quote(raw_value, safe='')
        nonce = secrets.token_hex(12)
        uri = f"/dynamic/{path_a}/{path_b}?{key}={value}&nonce={nonce}"
        expected = sign(uri)

        req = urllib.request.Request(f"http://127.0.0.1:8080{uri}")
        with urllib.request.urlopen(req, timeout=2.0) as response:
            assert response.status == 200
            data = json.loads(response.read().decode('utf-8'))

        assert data.get("HTTP_X_CUSTOM_SIGNATURE") == expected
        proof = data.get('__backend_proof')
        assert proof, "Response did not contain the backend's per-request proof"
        assert (uri, expected, proof) in dummy_backend.records, (
            "The exact randomly generated request was not forwarded to port 9000 "
            "with the correct signature"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
