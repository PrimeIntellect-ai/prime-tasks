#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import hashlib
import hmac
import json
import os
import random
import secrets
import subprocess

import pytest


def test_auth_filter_exists_and_executable():
    binary_path = "/home/user/auth_filter"
    assert os.path.exists(binary_path), f"The binary {binary_path} does not exist. Did you compile your Go code?"
    assert os.path.isfile(binary_path), f"{binary_path} is not a file."
    assert os.access(binary_path, os.X_OK), f"The binary {binary_path} is not executable."


def test_adversarial_corpus():
    binary_path = "/home/user/auth_filter"
    evil_dir = "/app/evil_tokens"
    clean_dir = "/app/clean_tokens"

    assert os.path.exists(evil_dir), f"Evil tokens directory {evil_dir} is missing."
    assert os.path.exists(clean_dir), f"Clean tokens directory {clean_dir} is missing."

    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]
    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]

    assert len(evil_files) > 0, "No evil tokens found to test."
    assert len(clean_files) > 0, "No clean tokens found to test."

    evil_bypassed = []
    clean_rejected = []

    # Test evil tokens (expect exit code 1)
    for evil_file in evil_files:
        result = subprocess.run([binary_path, evil_file], capture_output=True)
        if result.returncode != 1:
            evil_bypassed.append(os.path.basename(evil_file))

    # Test clean tokens (expect exit code 0)
    for clean_file in clean_files:
        result = subprocess.run([binary_path, clean_file], capture_output=True)
        if result.returncode != 0:
            clean_rejected.append(os.path.basename(clean_file))

    error_messages = []
    if evil_bypassed:
        error_messages.append(f"{len(evil_bypassed)} of {len(evil_files)} evil tokens bypassed the filter: {', '.join(evil_bypassed)}")
    if clean_rejected:
        error_messages.append(f"{len(clean_rejected)} of {len(clean_files)} clean tokens were rejected by the filter: {', '.join(clean_rejected)}")

    if error_messages:
        pytest.fail(" | ".join(error_messages))


def _b64url(data):
    return base64.urlsafe_b64encode(data).decode("ascii").rstrip("=")


def _json_part(value):
    return _b64url(json.dumps(value, separators=(",", ":"), sort_keys=True).encode("utf-8"))


def _hs256(payload, key):
    header_part = _json_part({"alg": "HS256", "typ": "JWT"})
    payload_part = _json_part(payload)
    signing_input = f"{header_part}.{payload_part}".encode("ascii")
    signature = hmac.new(key, signing_input, hashlib.sha256).digest()
    return f"{header_part}.{payload_part}.{_b64url(signature)}"


def _none_token(payload):
    return f"{_json_part({'alg': 'none', 'typ': 'JWT'})}.{_json_part(payload)}."


def test_fresh_randomized_tokens(tmp_path):
    binary_path = "/home/user/auth_filter"
    leaked_key = b"z9x8c7v6b5n4m3"
    cases = []

    # Use matching benign claims with different signing keys so classification
    # requires detecting signatures made with the leaked fallback key.
    for _ in range(6):
        payload = {
            "user": "analyst-" + secrets.token_hex(8),
            "admin": False,
            "nonce": secrets.token_hex(16),
        }
        cases.append((_hs256(payload, secrets.token_bytes(32)), 0))
        cases.append((_hs256(payload, leaked_key), 1))

    # Exercise the algorithm bypass independently of filenames and admin claims.
    for _ in range(3):
        payload = {
            "user": "viewer-" + secrets.token_hex(8),
            "admin": False,
            "nonce": secrets.token_hex(16),
        }
        cases.append((_none_token(payload), 1))

    # A validly signed token is still evil when a claim contains traversal.
    for _ in range(3):
        payload = {
            "user": "../../../../etc/" + secrets.token_hex(4),
            "admin": False,
            "nonce": secrets.token_hex(16),
        }
        cases.append((_hs256(payload, secrets.token_bytes(32)), 1))

    random.SystemRandom().shuffle(cases)
    failures = []
    for token, expected in cases:
        # Opaque random names in one shared directory reveal no expected class.
        token_path = tmp_path / (secrets.token_hex(16) + ".dat")
        token_path.write_text(token, encoding="utf-8")
        try:
            result = subprocess.run(
                [binary_path, str(token_path.resolve())],
                capture_output=True,
                timeout=5,
            )
            actual = result.returncode
        except subprocess.TimeoutExpired:
            actual = "timeout"
        if actual != expected:
            failures.append(f"{token_path.name}: expected {expected}, got {actual}")

    assert not failures, "Fresh-token classification failures: " + "; ".join(failures)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
