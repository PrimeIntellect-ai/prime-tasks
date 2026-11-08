#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import base64
import hmac
import hashlib
import subprocess
import time
import random
import pytest

SCRIPT_PATH = "/home/user/forge.sh"
SECRET_KEY = b"s3cr3t_k3y_991"

def base64url_decode(input_str):
    rem = len(input_str) % 4
    if rem > 0:
        input_str += '=' * (4 - rem)
    return base64.urlsafe_b64decode(input_str)

def verify_token(token, timestamp):
    try:
        parts = token.strip().split('.')
        if len(parts) != 3:
            return False

        header_b64, payload_b64, sig_b64 = parts

        # Check payload
        payload_json = base64url_decode(payload_b64).decode('utf-8')
        payload = json.loads(payload_json)

        if payload.get("user") != "admin":
            return False
        if payload.get("exp") != timestamp + 3600:
            return False

        # Check signature
        message = f"{header_b64}.{payload_b64}".encode('utf-8')
        expected_sig = hmac.new(SECRET_KEY, message, hashlib.sha256).digest()
        expected_sig_b64 = base64.urlsafe_b64encode(expected_sig).decode('utf-8').rstrip('=')

        # Compare signatures (allowing for padding differences if any, though standard is no padding)
        sig_decoded = base64url_decode(sig_b64)
        if sig_decoded != expected_sig:
            return False

        return True
    except Exception:
        return False

def test_forge_script_accuracy():
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script at {SCRIPT_PATH} is not executable"

    num_tests = 50
    correct = 0

    base_time = int(time.time())

    for i in range(num_tests):
        ts = base_time + random.randint(1000, 100000)

        try:
            result = subprocess.run(
                [SCRIPT_PATH, str(ts)],
                capture_output=True,
                text=True,
                timeout=5
            )
            token = result.stdout.strip()

            if verify_token(token, ts):
                correct += 1
        except subprocess.TimeoutExpired:
            continue
        except Exception:
            continue

    accuracy = correct / num_tests
    assert accuracy >= 0.95, f"Accuracy {accuracy:.2f} is below the threshold of 0.95. ({correct}/{num_tests} correct)"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
