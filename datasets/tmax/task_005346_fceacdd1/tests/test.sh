#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import hashlib
import json
import os
import stat
import subprocess
import pytest


def test_attacker_ip_extracted():
    ip_file = "/home/user/incident_report/attacker_ip.txt"
    assert os.path.isfile(ip_file), f"File not found: {ip_file}"
    with open(ip_file, "r") as f:
        content = f.read().strip()
    assert content == "10.13.37.99", f"Expected attacker IP '10.13.37.99', but got '{content}'"


def test_blocklist_updated():
    blocklist_path = "/home/user/app/config/blocklist.json"
    assert os.path.isfile(blocklist_path), f"File not found: {blocklist_path}"
    with open(blocklist_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Blocklist file {blocklist_path} is not valid JSON.")
    assert isinstance(data, list), "Blocklist must be a JSON array."
    assert "198.51.100.23" in data, "Original IP '198.51.100.23' is missing from the blocklist."
    assert "10.13.37.99" in data, "Attacker IP '10.13.37.99' was not added to the blocklist."


def test_auth_py_remediated():
    auth_py_path = "/home/user/app/auth.py"
    assert os.path.isfile(auth_py_path), f"File not found: {auth_py_path}"

    test_script = r'''
import base64
import json
import secrets
import sys
import jwt

sys.path.insert(0, "/home/user/app")
import auth

# Verify decode_token actually delegates to PyJWT with exactly HS256 allowed.
calls = []
marker = secrets.token_hex(16)
def fake_decode(*args, **kwargs):
    calls.append((args, kwargs))
    return {"marker": marker}

auth.jwt.decode = fake_decode
probe_token = secrets.token_urlsafe(30)
probe_secret = secrets.token_urlsafe(30)
result = auth.decode_token(probe_token, probe_secret)
assert result == {"marker": marker}
assert len(calls) == 1
args, kwargs = calls[0]
assert len(args) >= 2 and args[0] == probe_token and args[1] == probe_secret
allowed = kwargs.get("algorithms")
assert isinstance(allowed, (list, tuple, set, frozenset))
assert len(allowed) == 1 and set(allowed) == {"HS256"}
assert kwargs.get("verify", True) is not False
assert not (isinstance(kwargs.get("options"), dict) and kwargs["options"].get("verify_signature") is False)

# Restore the real PyJWT module and exercise unpredictable tokens.
auth.jwt = jwt
secret = secrets.token_urlsafe(32)
claims = {"user": secrets.token_hex(8), "role": "user", "nonce": secrets.token_hex(16)}
valid = jwt.encode(claims, secret, algorithm="HS256")
decoded = auth.decode_token(valid, secret)
assert decoded["nonce"] == claims["nonce"]

bad_tokens = []
bad_tokens.append(jwt.encode(claims, secret, algorithm="HS384"))

enc = lambda obj: base64.urlsafe_b64encode(json.dumps(obj, separators=(",", ":")).encode()).rstrip(b"=").decode()
bad_tokens.append(enc({"alg": "none", "typ": "JWT"}) + "." + enc(claims) + ".")
bad_tokens.append("eyJhbGciOiJub25lIiwidHlwIjoiSldUIn0.eyJ1c2VyIjoiYmFkZ3V5Iiwicm9sZSI6ImFkbWluIn0.")

for token in bad_tokens:
    try:
        auth.decode_token(token, secret)
    except Exception:
        pass
    else:
        raise AssertionError("decode_token accepted a token not signed with HS256")

try:
    auth.decode_token(valid, secrets.token_urlsafe(32))
except Exception:
    pass
else:
    raise AssertionError("decode_token accepted an HS256 token with the wrong secret")

print("SECURE")
'''
    result = subprocess.run(["python3", "-c", test_script], capture_output=True, text=True)
    assert result.returncode == 0, (
        "auth.py did not implement working HS256-only verification.\n"
        f"stdout: {result.stdout}\nstderr: {result.stderr}"
    )
    assert "SECURE" in result.stdout, "auth.py did not complete the HS256-only checks."


def test_new_secret_generated():
    secret_path = "/home/user/app/config/new_secret.key"
    assert os.path.isfile(secret_path), f"File not found: {secret_path}"

    st = os.stat(secret_path)
    perms = stat.S_IMODE(st.st_mode)
    assert perms == 0o400, f"Expected file permissions to be 400, but got {oct(perms)}"

    with open(secret_path, "r") as f:
        content = f.read().strip()
    try:
        decoded = base64.b64decode(content, validate=True)
    except Exception:
        pytest.fail(f"Content of {secret_path} is not valid base64.")

    assert len(decoded) == 32, f"Expected decoded secret to be exactly 32 bytes, but got {len(decoded)} bytes."

    # Reject fixed, low-entropy, and obvious deterministic placeholder values.
    assert len(set(decoded)) >= 16, "The new secret is a low-entropy repeated-byte placeholder."
    assert decoded != bytes(range(32)), "The new secret is an obvious deterministic sequence."
    assert decoded != bytes(range(31, -1, -1)), "The new secret is an obvious deterministic sequence."
    with open("/home/user/app/config/secret.key", "rb") as f:
        old_secret = f.read().strip()
    weak_derivations = {
        old_secret.ljust(32, b"\0")[:32],
        hashlib.sha256(old_secret).digest(),
        hashlib.sha256(b"new_secret").digest(),
        hashlib.sha256(b"secret").digest(),
    }
    assert decoded not in weak_derivations, "The new secret was not independently and securely rotated."


def test_compromised_key_identified():
    report_path = "/home/user/incident_report/compromised_key.txt"
    assert os.path.isfile(report_path), f"File not found: {report_path}"
    with open(report_path, "r") as f:
        content = f.read().strip()
    assert content == "key_v2.pem", f"Expected compromised key to be 'key_v2.pem', but got '{content}'"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
