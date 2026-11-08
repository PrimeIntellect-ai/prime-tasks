#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import hashlib
import hmac
import json
import os
import secrets
import string
import subprocess
import sys
import tempfile
import time
import pytest

VENDORED_PATH = "/app/vendored/pyjwt-2.8.0"
REDACTOR = "/home/user/redactor.py"


def b64url_decode(value):
    return base64.urlsafe_b64decode(value + "=" * (-len(value) % 4))


def independently_decode_hs256(token, secret, verify_exp=True):
    parts = token.split(".")
    assert len(parts) == 3, "Captured token is not a three-part JWT"
    header = json.loads(b64url_decode(parts[0]).decode("utf-8"))
    payload = json.loads(b64url_decode(parts[1]).decode("utf-8"))
    assert header.get("alg") == "HS256", "Unexpected JWT algorithm"
    expected = hmac.new(
        secret.encode("utf-8"),
        (parts[0] + "." + parts[1]).encode("ascii"),
        hashlib.sha256,
    ).digest()
    signature_valid = hmac.compare_digest(expected, b64url_decode(parts[2]))
    if not signature_valid:
        raise ValueError("invalid signature")
    if verify_exp and "exp" in payload and float(payload["exp"]) <= time.time():
        raise ValueError("expired token")
    return payload


def test_stage1_vendored_package_fixed():
    api_jwt_path = "/app/vendored/pyjwt-2.8.0/jwt/api_jwt.py"
    assert os.path.isfile(api_jwt_path), f"Missing api_jwt.py at {api_jwt_path}"

    with open(api_jwt_path, "r") as f:
        content = f.read()

    assert 'raise DecodeError("Task perturbation")' not in content, "The deliberate perturbation was not removed from api_jwt.py"

    # Exercise the repaired vendored decoder with unpredictable runtime values.
    probe = r'''
import base64, hashlib, hmac, json, os, secrets, sys, time
import jwt
vendored = os.path.realpath(sys.argv[1])
assert os.path.realpath(jwt.__file__).startswith(vendored + os.sep)

def enc(obj):
    raw = json.dumps(obj, separators=(",", ":")).encode()
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode()

def token(payload, secret):
    signing = enc({"alg":"HS256","typ":"JWT"}) + "." + enc(payload)
    sig = hmac.new(secret.encode(), signing.encode(), hashlib.sha256).digest()
    return signing + "." + base64.urlsafe_b64encode(sig).rstrip(b"=").decode()

secret = secrets.token_urlsafe(31)
uid = secrets.token_hex(13)
valid = token({"user_id": uid, "exp": int(time.time()) + 600}, secret)
assert jwt.decode(valid, secret, algorithms=["HS256"])["user_id"] == uid
try:
    jwt.decode(valid, secrets.token_urlsafe(31), algorithms=["HS256"])
except Exception:
    pass
else:
    raise AssertionError("Vendored decoder accepted an invalid signature")
expired = token({"user_id": uid, "exp": int(time.time()) - 600}, secret)
try:
    jwt.decode(expired, secret, algorithms=["HS256"])
except Exception:
    pass
else:
    raise AssertionError("Vendored decoder accepted an expired token")
'''
    env = os.environ.copy()
    env["PYTHONPATH"] = VENDORED_PATH
    result = subprocess.run(
        [sys.executable, "-c", probe, VENDORED_PATH],
        env=env,
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, result.stdout + result.stderr


def test_stage2_and_4_valid_users_and_checksum():
    # Preserve the original vendored-package-based assertion.
    if VENDORED_PATH not in sys.path:
        sys.path.insert(0, VENDORED_PATH)

    try:
        import jwt
    except ImportError:
        pytest.fail("Failed to import jwt from the vendored package.")

    secret_path = "/home/user/jwt_secret.key"
    tokens_path = "/home/user/captured_tokens.txt"
    users_log_path = "/home/user/valid_users.log"
    checksum_path = "/home/user/audit_checksum.txt"

    assert os.path.isfile(secret_path), "Missing jwt_secret.key"
    assert os.path.isfile(tokens_path), "Missing captured_tokens.txt"
    assert os.path.isfile(users_log_path), "Missing valid_users.log"
    assert os.path.isfile(checksum_path), "Missing audit_checksum.txt"

    with open(secret_path, "r") as f:
        secret = f.read().strip()
    with open(tokens_path, "r") as f:
        tokens = [line.strip() for line in f if line.strip()]

    expected_users = []
    for token in tokens:
        try:
            decoded = jwt.decode(token, secret, algorithms=["HS256"])
            if "user_id" in decoded:
                expected_users.append(str(decoded["user_id"]))
        except Exception:
            pass
    expected_users.sort()
    expected_log_content = "\n".join(expected_users) + ("\n" if expected_users else "")

    with open(users_log_path, "r") as f:
        actual_log_content = f.read()
    assert actual_log_content.strip() == expected_log_content.strip(), "valid_users.log does not contain the correct sorted user_ids."

    expected_checksum = hashlib.sha256(actual_log_content.encode("utf-8")).hexdigest()
    with open(checksum_path, "r") as f:
        actual_checksum = f.read().strip()
    assert actual_checksum == expected_checksum, "audit_checksum.txt does not match the SHA-256 checksum of valid_users.log"

    # Independently validate the immutable fixture semantics rather than trusting
    # code from the agent-modifiable vendored decoder.
    assert secret == "super_secret_compliance_key_2023!", "jwt_secret.key was altered"
    assert len(tokens) == 3, "captured_tokens.txt was altered"

    payloads = []
    for token in tokens:
        payloads.append(json.loads(b64url_decode(token.split(".")[1]).decode("utf-8")))
    by_user = {str(p.get("user_id")): (t, p) for t, p in zip(tokens, payloads)}
    assert set(by_user) == {"user_001", "user_002", "user_003"}, "Captured token fixture was altered"

    independently_decode_hs256(by_user["user_001"][0], secret, verify_exp=False)
    independently_decode_hs256(by_user["user_002"][0], secret, verify_exp=False)
    assert float(by_user["user_002"][1]["exp"]) <= time.time(), "Expected user_002 token to be expired"
    with pytest.raises(ValueError):
        independently_decode_hs256(by_user["user_003"][0], secret, verify_exp=False)

    independent_users = []
    for token in tokens:
        try:
            payload = independently_decode_hs256(token, secret)
            if "user_id" in payload:
                independent_users.append(str(payload["user_id"]))
        except (ValueError, AssertionError, KeyError, TypeError, json.JSONDecodeError):
            pass
    independent_users.sort()
    independent_content = "\n".join(independent_users) + ("\n" if independent_users else "")
    assert actual_log_content == independent_content, "valid_users.log is incorrect under independent HS256 validation"


def run_redactor(input_data, tmpdir, name):
    input_path = os.path.join(tmpdir, name + ".in")
    output_path = os.path.join(tmpdir, name + ".out")
    with open(input_path, "w", encoding="utf-8", newline="") as f:
        f.write(input_data)
    result = subprocess.run(
        [sys.executable, REDACTOR, input_path, output_path],
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, result.stdout + result.stderr
    assert os.path.isfile(output_path), "Redactor did not create its requested output file"
    with open(output_path, "r", encoding="utf-8", newline="") as f:
        return f.read()


def make_runtime_jwt():
    def enc(obj):
        raw = json.dumps(obj, separators=(",", ":")).encode("utf-8")
        return base64.urlsafe_b64encode(raw).rstrip(b"=").decode("ascii")
    header = enc({"alg": "HS256", "typ": "JWT"})
    payload = enc({"sub": secrets.token_hex(15), "iat": int(time.time())})
    signature = base64.urlsafe_b64encode(secrets.token_bytes(32)).rstrip(b"=").decode("ascii")
    return header + "." + payload + "." + signature


def test_stage3_redactor_adversarial_corpus():
    assert os.path.isfile(REDACTOR), f"Missing redactor script at {REDACTOR}"

    evil_corpus = "/app/corpora/evil/"
    clean_corpus = "/app/corpora/clean/"
    assert os.path.isdir(evil_corpus), "Missing evil corpus directory"
    assert os.path.isdir(clean_corpus), "Missing clean corpus directory"

    evil_files = [f for f in os.listdir(evil_corpus) if os.path.isfile(os.path.join(evil_corpus, f))]
    clean_files = [f for f in os.listdir(clean_corpus) if os.path.isfile(os.path.join(clean_corpus, f))]
    evil_bypassed = []
    clean_modified = []

    with tempfile.TemporaryDirectory() as tmpdir:
        for filename in evil_files:
            input_path = os.path.join(evil_corpus, filename)
            output_path = os.path.join(tmpdir, filename)
            result = subprocess.run([sys.executable, REDACTOR, input_path, output_path], capture_output=True, text=True)
            if result.returncode != 0 or not os.path.isfile(output_path):
                evil_bypassed.append(filename)
                continue
            with open(input_path, "r") as f:
                input_data = f.read()
            with open(output_path, "r") as f:
                output_data = f.read()
            if input_data == output_data or "[REDACTED]" not in output_data:
                evil_bypassed.append(filename)

        for filename in clean_files:
            input_path = os.path.join(clean_corpus, filename)
            output_path = os.path.join(tmpdir, filename)
            result = subprocess.run([sys.executable, REDACTOR, input_path, output_path], capture_output=True, text=True)
            if result.returncode != 0 or not os.path.isfile(output_path):
                clean_modified.append(filename)
                continue
            with open(input_path, "r") as f:
                input_data = f.read()
            with open(output_path, "r") as f:
                output_data = f.read()
            if input_data != output_data:
                clean_modified.append(filename)

    error_msgs = []
    if evil_bypassed:
        error_msgs.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        error_msgs.append(f"{len(clean_modified)} of {len(clean_files)} clean modified: {', '.join(clean_modified)}")
    if error_msgs:
        pytest.fail(" | ".join(error_msgs))


def test_stage3_generated_exact_cases():
    alphabet = string.ascii_uppercase + string.digits
    aws_key = "AKIA" + "".join(secrets.choice(alphabet) for _ in range(16))
    jwt_token = make_runtime_jwt()

    sensitive = (
        f"aws={aws_key}; token={jwt_token}\n"
        "cards: 4222222222222, 4111-2222-3333-4444, "
        "4111 1111 1111 1111, and 4000000000000000006.\n"
        f"Repeated {aws_key} and {jwt_token}.\n"
    )
    expected = (
        "aws=[REDACTED]; token=[REDACTED]\n"
        "cards: [REDACTED], [REDACTED], [REDACTED], and [REDACTED].\n"
        "Repeated [REDACTED] and [REDACTED].\n"
    )

    clean = (
        f"Git commit {secrets.token_hex(20)} deployed.\n"
        "UUID 123e4567-e89b-12d3-a456-426614174000 processed successfully.\n"
        "Transaction ID: TXN-9876543210ABCDEF\n"
        "Debug IDs: deadbeefcafebabefeedface and 123456789012 and 12345678901234567890.\n"
        "Near AWS keys: AKIA1234567890ABCDE and AKIA1234567890ABCDEFG.\n"
        "Not JWTs: eyJhbGciOiJIUzI1NiJ9.only-two-parts and abJhbGciOiJIUzI1NiJ9.x.y\n"
    )

    with tempfile.TemporaryDirectory() as tmpdir:
        assert run_redactor(sensitive, tmpdir, "generated-sensitive") == expected
        assert run_redactor(clean, tmpdir, "generated-clean") == clean
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
