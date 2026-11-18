#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import base64
import hmac
import hashlib
import time
import pytest


def decode_b64url(s):
    s = s.replace('-', '+').replace('_', '/')
    padding = '=' * ((4 - (len(s) % 4)) % 4)
    return base64.b64decode(s + padding)


def test_jwt_token_validity():
    token_path = "/home/user/admin_token.txt"
    assert os.path.exists(token_path), f"Token file missing at {token_path}"

    with open(token_path, "r") as f:
        token = f.read().strip()

    parts = token.split('.')
    assert len(parts) == 3, "Token does not have 3 parts separated by dots (invalid JWT format)."
    header_b64, payload_b64, signature_b64 = parts

    try:
        header = json.loads(decode_b64url(header_b64))
        payload = json.loads(decode_b64url(payload_b64))
    except Exception as e:
        pytest.fail(f"Failed to decode JWT header or payload: {e}")

    assert header.get("alg") == "HS256", f"Expected alg 'HS256', got '{header.get('alg')}'"
    assert payload.get("sub") == "admin", f"Expected sub 'admin', got '{payload.get('sub')}'"
    exp = payload.get("exp")
    assert exp is not None, "JWT is missing 'exp' claim."
    assert exp > time.time(), f"JWT 'exp' ({exp}) is not in the future."

    message = f"{header_b64}.{payload_b64}".encode('utf-8')
    secret = b"s3cr3t_k3y_v3ry_s3cur3_1337"
    expected_sig = base64.urlsafe_b64encode(
        hmac.new(secret, message, hashlib.sha256).digest()
    ).decode('utf-8').rstrip('=')
    assert signature_b64 == expected_sig, "JWT signature is invalid. Did you use the correct extracted secret?"


def test_scanner_accuracy():
    results_path = "/home/user/scan_results.json"
    truth_path = "/tests/.ground_truth.json"

    assert os.path.exists(results_path), f"Scan results missing at {results_path}"
    assert os.path.exists(truth_path), f"Ground truth missing at {truth_path}"

    try:
        with open(results_path, "r") as f:
            preds = json.load(f)
    except Exception as e:
        pytest.fail(f"Could not load {results_path} as JSON: {e}")

    with open(truth_path, "r") as f:
        truth = json.load(f)

    correct = 0
    total = len(truth)
    assert total > 0, "Ground truth is empty."
    for k, v in truth.items():
        if preds.get(k) == v:
            correct += 1

    accuracy = correct / total
    assert accuracy >= 0.95, f"Scanner accuracy {accuracy:.4f} is below the required threshold of 0.95."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
