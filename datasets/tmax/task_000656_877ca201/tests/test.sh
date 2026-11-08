#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
import json
import base64
import hmac
import hashlib
import urllib.request
import urllib.error
import socket
import tempfile
import uuid
import random
import pytest

DETECTOR_BIN = "/home/user/detector/target/debug/detector"
EVIL_CORPUS_DIR = "/home/user/corpora/evil"
CLEAN_CORPUS_DIR = "/home/user/corpora/clean"
BACKEND_DIR = "/home/user/app/backend"


def b64url(data):
    return base64.urlsafe_b64encode(data).decode().rstrip('=')


def create_jwt(header, payload, secret=None, digest=hashlib.sha256):
    b64_header = b64url(json.dumps(header, separators=(",", ":")).encode())
    b64_payload = b64url(json.dumps(payload, separators=(",", ":")).encode())
    msg = f"{b64_header}.{b64_payload}"
    if secret is not None:
        sig = hmac.new(secret.encode(), msg.encode(), digest).digest()
        return f"{msg}.{b64url(sig)}"
    return f"{msg}."


def run_detector(path):
    result = subprocess.run(
        [DETECTOR_BIN, path], capture_output=True, text=True, timeout=3
    )
    return result.stdout.strip()


def test_detector_exists_and_executable():
    assert os.path.isfile(DETECTOR_BIN), f"Detector binary not found at {DETECTOR_BIN}"
    assert os.access(DETECTOR_BIN, os.X_OK), f"Detector binary at {DETECTOR_BIN} is not executable"


def test_detector_corpus():
    evil_files = [os.path.join(EVIL_CORPUS_DIR, f) for f in os.listdir(EVIL_CORPUS_DIR) if os.path.isfile(os.path.join(EVIL_CORPUS_DIR, f))]
    clean_files = [os.path.join(CLEAN_CORPUS_DIR, f) for f in os.listdir(CLEAN_CORPUS_DIR) if os.path.isfile(os.path.join(CLEAN_CORPUS_DIR, f))]

    assert len(evil_files) > 0, "Evil corpus is empty"
    assert len(clean_files) > 0, "Clean corpus is empty"

    evil_bypassed = []
    for fpath in evil_files:
        try:
            if run_detector(fpath) != "EVIL":
                evil_bypassed.append(os.path.basename(fpath))
        except Exception as e:
            evil_bypassed.append(f"{os.path.basename(fpath)} (Error: {e})")

    clean_modified = []
    for fpath in clean_files:
        try:
            if run_detector(fpath) != "CLEAN":
                clean_modified.append(os.path.basename(fpath))
        except Exception as e:
            clean_modified.append(f"{os.path.basename(fpath)} (Error: {e})")

    error_msgs = []
    if evil_bypassed:
        error_msgs.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        error_msgs.append(f"{len(clean_modified)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_modified)}")
    if error_msgs:
        pytest.fail(" | ".join(error_msgs))


def test_detector_generated_tokens_at_opaque_paths():
    nonce = uuid.uuid4().hex
    cases = []

    for i in range(5):
        payload = {"user_id": f"member-{nonce}-{i}", "nonce": uuid.uuid4().hex}
        cases.append((create_jwt({"typ": "JWT", "alg": "HS256"}, payload, "secret_key_123"), "CLEAN"))

    for alg in ["none", "None", "NONE", "nOnE"]:
        payload = {"user_id": f"member-{uuid.uuid4().hex}"}
        cases.append((create_jwt({"alg": alg, "typ": "JWT"}, payload), "EVIL"))

    for i in range(4):
        payload = {"user_id": f"member-{uuid.uuid4().hex}"}
        wrong_key = f"wrong-{uuid.uuid4().hex}"
        cases.append((create_jwt({"alg": "HS256", "typ": "JWT"}, payload, wrong_key), "EVIL"))

    injections = ["x ' oR 7=7", "prefix uNiOn SeLeCt password", "abc ; dRoP table audit"]
    for injection in injections:
        payload = {"user_id": f"{uuid.uuid4().hex} {injection}"}
        cases.append((create_jwt({"alg": "HS256", "typ": "JWT"}, payload, "secret_key_123"), "EVIL"))

    unsigned_hs256 = create_jwt(
        {"alg": "HS256", "typ": "JWT"},
        {"user_id": f"member-{uuid.uuid4().hex}"},
        None,
    )
    cases.append((unsigned_hs256, "EVIL"))
    cases.append((create_jwt(
        {"alg": "HS384", "typ": "JWT"},
        {"user_id": f"member-{uuid.uuid4().hex}"},
        "secret_key_123",
        hashlib.sha384,
    ), "EVIL"))
    cases.append(("not-a-jwt-" + uuid.uuid4().hex, "EVIL"))

    random.SystemRandom().shuffle(cases)
    with tempfile.TemporaryDirectory(prefix="jwt-check-") as tmpdir:
        failures = []
        for token, expected in cases:
            # Names are deliberately random and contain no classification hint.
            path = os.path.join(tmpdir, uuid.uuid4().hex)
            with open(path, "w") as f:
                f.write(token + ("\n" if random.choice([True, False]) else ""))
            try:
                actual = run_detector(path)
            except Exception as e:
                failures.append(f"{expected}: error {e}")
                continue
            if actual != expected:
                failures.append(f"expected {expected}, got {actual!r}")
        assert not failures, "Generated detector cases failed: " + "; ".join(failures)


def test_backend_bound_localhost():
    try:
        result = subprocess.run(["ss", "-tlnp"], capture_output=True, text=True)
        lines = result.stdout.splitlines()
        found_8080 = False
        bound_to_localhost = False
        for line in lines:
            if ":8080" in line:
                found_8080 = True
                if "127.0.0.1:8080" in line:
                    bound_to_localhost = True
                elif "0.0.0.0:8080" in line or "*:8080" in line:
                    pytest.fail("Backend is still bound to 0.0.0.0:8080 (externally accessible)")
        assert found_8080, "Port 8080 is not listening. Is the backend running?"
        assert bound_to_localhost, "Backend is not bound to 127.0.0.1:8080"
    except FileNotFoundError:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(1)
        try:
            pass
        finally:
            s.close()


def test_auth_module_is_strict_and_main_uses_it():
    main_path = os.path.join(BACKEND_DIR, "src", "main.rs")
    auth_path = os.path.join(BACKEND_DIR, "src", "auth.rs")
    assert os.path.isfile(main_path)
    assert os.path.isfile(auth_path)

    with open(main_path) as f:
        source = f.read()
    source = re.sub(r"/\*.*?\*/", "", source, flags=re.S)
    source = re.sub(r"//.*", "", source)
    assert re.search(r"auth\s*::\s*(?:\{\s*)?verify_token", source), \
        "main.rs does not use auth.rs verify_token"

    probe_dir = os.path.join(BACKEND_DIR, "src", "bin")
    probe_path = os.path.join(probe_dir, "__verifier_auth_probe.rs")
    os.makedirs(probe_dir, exist_ok=True)
    probe_source = r'''
#[path = "../auth.rs"]
mod auth;

fn main() {
    for token in std::env::args().skip(1) {
        println!("{}", auth::verify_token(&token));
    }
}
'''
    valid = create_jwt({"alg": "HS256", "typ": "JWT"}, {"user_id": "probe-" + uuid.uuid4().hex}, "secret_key_123")
    bad_sig = create_jwt({"alg": "HS256", "typ": "JWT"}, {"user_id": "probe-" + uuid.uuid4().hex}, "wrong-" + uuid.uuid4().hex)
    none_token = create_jwt({"alg": "none", "typ": "JWT"}, {"user_id": "probe-" + uuid.uuid4().hex})
    hs384 = create_jwt({"alg": "HS384", "typ": "JWT"}, {"user_id": "probe-" + uuid.uuid4().hex}, "secret_key_123", hashlib.sha384)
    try:
        with open(probe_path, "w") as f:
            f.write(probe_source)
        result = subprocess.run(
            ["cargo", "run", "--quiet", "--bin", "__verifier_auth_probe", "--", valid, bad_sig, none_token, hs384],
            cwd=BACKEND_DIR, capture_output=True, text=True, timeout=180,
        )
        assert result.returncode == 0, f"Could not execute auth.rs verifier: {result.stderr}"
        assert result.stdout.splitlines() == ["true", "false", "false", "false"], \
            f"auth.rs did not strictly validate generated tokens: {result.stdout!r}"
    finally:
        try:
            os.remove(probe_path)
        except FileNotFoundError:
            pass


def api_request(token=None):
    url = "http://localhost:8000/api/secure?nonce=" + uuid.uuid4().hex
    req = urllib.request.Request(url)
    if token is not None:
        req.add_header("Authorization", f"Bearer {token}")
    try:
        with urllib.request.urlopen(req, timeout=3) as response:
            return response.status
    except urllib.error.HTTPError as e:
        return e.code


def test_api_secure_endpoint():
    valid_header = {"alg": "HS256", "typ": "JWT"}
    payload = {"user_id": "user123"}
    valid_jwt = create_jwt(valid_header, payload, "secret_key_123")
    none_jwt = create_jwt({"alg": "none", "typ": "JWT"}, payload, None)

    status = api_request(valid_jwt)
    assert status == 200, f"Expected 200 OK for valid JWT, got {status}"

    status = api_request(none_jwt)
    assert status in [401, 403], f"Expected 401 or 403 for alg=none JWT, got {status}"


def test_api_generated_authentication_cases():
    for _ in range(3):
        token = create_jwt(
            {"typ": "JWT", "alg": "HS256"},
            {"user_id": "api-" + uuid.uuid4().hex, "nonce": uuid.uuid4().hex},
            "secret_key_123",
        )
        assert api_request(token) == 200, "Generated valid HS256 token was rejected"

    rejected = []
    for _ in range(3):
        rejected.append(create_jwt(
            {"alg": "HS256", "typ": "JWT"},
            {"user_id": "api-" + uuid.uuid4().hex},
            "wrong-" + uuid.uuid4().hex,
        ))
    for alg in ["none", "NONE", "None"]:
        rejected.append(create_jwt(
            {"alg": alg, "typ": "JWT"},
            {"user_id": "api-" + uuid.uuid4().hex},
            None,
        ))
    rejected.append(create_jwt(
        {"alg": "HS384", "typ": "JWT"},
        {"user_id": "api-" + uuid.uuid4().hex},
        "secret_key_123",
        hashlib.sha384,
    ))
    rejected.append(create_jwt(
        {"alg": "HS256", "typ": "JWT"},
        {"user_id": "api-" + uuid.uuid4().hex},
        None,
    ))
    rejected.append("malformed." + uuid.uuid4().hex)

    for token in rejected:
        status = api_request(token)
        assert status in [401, 403], f"Malicious JWT was not rejected; got status {status}"

    status = api_request(None)
    assert status in [401, 403], f"Missing Authorization header was not rejected; got status {status}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
