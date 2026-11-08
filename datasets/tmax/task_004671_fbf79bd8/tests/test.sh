#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import json
import hashlib
import random
import string
import base64
import secrets
import urllib.request
import urllib.error
from http.server import HTTPServer, BaseHTTPRequestHandler
import threading
import time
import jwt
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa


def get_file_hash(filepath):
    with open(filepath, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


def b64url(data):
    return base64.urlsafe_b64encode(data).decode("ascii").rstrip("=")


def generate_fuzz_inputs():
    private_key_path = "/app/certs/private.pem"
    with open(private_key_path, "rb") as f:
        private_key = serialization.load_pem_private_key(f.read(), password=None)

    config_path = "/app/data/critical_config.json"
    correct_hash = get_file_hash(config_path)

    inputs = []
    random.seed(42)

    # Preserve the original fixed corpus.
    for _ in range(100):
        length = random.randint(10, 500)
        inputs.append(''.join(random.choices(string.ascii_letters + string.digits, k=length)))

        payload = {"file_hash": correct_hash, "rand": random.randint(1, 10000)}
        token = jwt.encode(payload, "wrong_secret", algorithm="HS256")
        inputs.append(token)

        header = b64url(b'{"alg":"none","typ":"JWT"}')
        payload_b64 = b64url(json.dumps(payload).encode())
        inputs.append(f"{header}.{payload_b64}.")

        bad_payload = {"file_hash": "badhash123", "rand": random.randint(1, 10000)}
        token = jwt.encode(bad_payload, private_key, algorithm="RS256")
        inputs.append(token)

        good_payload = {"file_hash": correct_hash, "rand": random.randint(1, 10000)}
        token = jwt.encode(good_payload, private_key, algorithm="RS256")
        inputs.append(token)

    # Add an unpredictable corpus that specifically exercises RSA signature
    # verification instead of allowing decisions based only on alg and claims.
    wrong_private_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    for _ in range(80):
        nonce = secrets.token_hex(secrets.randbelow(48) + 1)
        good_payload = {
            "file_hash": correct_hash,
            "nonce": nonce,
            "number": secrets.randbits(63),
        }

        # Correct alg and hash, but signed by an unrelated RSA key.
        inputs.append(jwt.encode(good_payload, wrong_private_key, algorithm="RS256"))

        # Start with a genuinely valid token and corrupt its signature.
        valid = jwt.encode(good_payload, private_key, algorithm="RS256")
        parts = valid.split(".")
        sig = parts[2]
        pos = secrets.randbelow(len(sig))
        replacement = "A" if sig[pos] != "A" else "B"
        inputs.append(parts[0] + "." + parts[1] + "." + sig[:pos] + replacement + sig[pos + 1:])

        # Syntactically plausible RS256 token with arbitrary signature bytes.
        header = b64url(json.dumps({"alg": "RS256", "typ": "JWT", "kid": nonce}, separators=(",", ":")).encode())
        payload = b64url(json.dumps(good_payload, separators=(",", ":")).encode())
        signature = b64url(secrets.token_bytes(secrets.randbelow(256) + 1))
        inputs.append(f"{header}.{payload}.{signature}")

        # Valid signatures with absent or incorrectly typed integrity claims.
        inputs.append(jwt.encode({"nonce": nonce}, private_key, algorithm="RS256"))
        inputs.append(jwt.encode({"file_hash": secrets.randbits(128), "nonce": nonce}, private_key, algorithm="RS256"))

        # Random three-part malformed inputs, including invalid base64url data.
        inputs.append(f"{secrets.token_urlsafe(12)}!{nonce}.{secrets.token_urlsafe(17)}.{secrets.token_urlsafe(23)}")

    return inputs


def test_completion_marker():
    marker = "/home/user/integration_done.log"
    assert os.path.isfile(marker), f"Completion marker missing at {marker}"
    with open(marker, "r", encoding="utf-8") as f:
        assert f.read().strip() == "READY", "integration_done.log must contain READY"


def test_fuzz_equivalence():
    agent_script = "/home/user/verify_token.py"
    oracle_bin = "/app/oracle/token_validator_bin"

    assert os.path.exists(agent_script), f"Agent script missing at {agent_script}"
    assert os.path.isfile(agent_script), f"Agent script is not a file: {agent_script}"
    assert os.path.exists(oracle_bin), f"Oracle binary missing at {oracle_bin}"

    inputs = generate_fuzz_inputs()

    for i, token in enumerate(inputs):
        oracle_proc = subprocess.run([oracle_bin], input=token.encode(), capture_output=True, timeout=10)
        oracle_out = oracle_proc.stdout.decode().strip()

        agent_proc = subprocess.run(["python3", agent_script], input=token.encode(), capture_output=True, timeout=10)
        agent_out = agent_proc.stdout.decode().strip()

        assert agent_proc.returncode == 0, f"Agent exited with {agent_proc.returncode} on input {i}"
        assert agent_out == oracle_out, f"Mismatch on input {i}:\nInput: {token}\nOracle: {oracle_out}\nAgent: {agent_out}"


class DummyBackend(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"BACKEND_SECRET")

    def log_message(self, format, *args):
        pass


def test_integration():
    server = HTTPServer(('127.0.0.1', 9000), DummyBackend)
    t = threading.Thread(target=server.serve_forever)
    t.daemon = True
    t.start()

    try:
        time.sleep(1)

        private_key_path = "/app/certs/private.pem"
        with open(private_key_path, "rb") as f:
            private_key = serialization.load_pem_private_key(f.read(), password=None)

        config_path = "/app/data/critical_config.json"
        correct_hash = get_file_hash(config_path)

        valid_payload = {"file_hash": correct_hash}
        valid_token = jwt.encode(valid_payload, private_key, algorithm="RS256")

        req = urllib.request.Request("http://127.0.0.1:8080/")
        try:
            urllib.request.urlopen(req)
            assert False, "Expected 401 for missing auth"
        except urllib.error.HTTPError as e:
            assert e.code == 401, f"Expected 401, got {e.code}"

        header = b64url(b'{"alg":"none","typ":"JWT"}')
        payload_b64 = b64url(json.dumps(valid_payload).encode())
        bad_token = f"{header}.{payload_b64}."

        req = urllib.request.Request("http://127.0.0.1:8080/")
        req.add_header("Authorization", f"Bearer {bad_token}")
        try:
            urllib.request.urlopen(req)
            assert False, "Expected 401 for alg=none"
        except urllib.error.HTTPError as e:
            assert e.code == 401, f"Expected 401, got {e.code}"

        req = urllib.request.Request("http://127.0.0.1:8080/")
        req.add_header("Authorization", f"Bearer {valid_token}")
        try:
            resp = urllib.request.urlopen(req)
            assert resp.code == 200, f"Expected 200, got {resp.code}"
            body = resp.read().decode()
            assert "BACKEND_SECRET" in body, "Did not receive backend response"
        except urllib.error.HTTPError as e:
            assert False, f"Expected 200 for valid token, got {e.code}"
    finally:
        server.shutdown()
        server.server_close()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
