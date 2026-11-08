#!/bin/bash
mkdir -p /logs/verifier

if (
    set -e

    test -f /home/user/audit.go
    test -f /home/user/tokens.txt
    test -f /home/user/legacy_auth

    original_tokens=$(mktemp)
    cp /home/user/tokens.txt "$original_tokens"
    cleanup() {
        cp "$original_tokens" /home/user/tokens.txt 2>/dev/null || true
        rm -f "$original_tokens" /tmp/audit_submission
    }
    trap cleanup EXIT

    cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import base64
import hashlib


def extract_key(binary_path):
    with open(binary_path, "rb") as f:
        content = f.read()

    prefix = b"XOR_KEY="
    idx = content.find(prefix)
    assert idx != -1, f"Could not find {prefix} in {binary_path}"

    key = content[idx + len(prefix) : idx + len(prefix) + 8]
    assert len(key) == 8, "Extracted key is less than 8 bytes"
    return key


def test_audit_trail_log_correctness():
    log_path = "/home/user/audit_trail.log"
    tokens_path = "/home/user/tokens.txt"
    binary_path = "/home/user/legacy_auth"

    assert os.path.isfile(log_path), f"The file {log_path} does not exist."
    assert os.path.isfile(tokens_path), f"The file {tokens_path} does not exist."
    assert os.path.isfile(binary_path), f"The file {binary_path} does not exist."

    key = extract_key(binary_path)

    with open(tokens_path, "r") as f:
        tokens = [line.strip() for line in f if line.strip()]

    expected_lines = []
    for token in tokens:
        decoded = base64.b64decode(token)
        decrypted = bytearray()
        for i, b in enumerate(decoded):
            decrypted.append(b ^ key[i % len(key)])

        decrypted_hex = decrypted.hex()
        sha256_hex = hashlib.sha256(decrypted).hexdigest()
        expected_lines.append(
            f"Original: {token} | DecryptedHex: {decrypted_hex} | SHA256: {sha256_hex}"
        )

    with open(log_path, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert len(actual_lines) == len(expected_lines), (
        f"Expected {len(expected_lines)} lines in {log_path}, but found {len(actual_lines)}."
    )

    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual == expected, (
            f"Line {i+1} in {log_path} is incorrect.\n"
            f"Expected: {expected}\nActual:   {actual}"
        )
TEST_EOF

    go build -o /tmp/audit_submission /home/user/audit.go

    # Require the submitted program itself to generate the log for the shipped tokens.
    rm -f /home/user/audit_trail.log
    (cd /home/user && timeout 20s /tmp/audit_submission)
    python3 -m pytest /tmp/test_final_state.py -x --tb=short

    # Exercise the compiled program on unpredictable token payloads.
    python3 - << 'PY_EOF'
import base64
import secrets

lengths = [1, 7, 8, 9, 17, 31, 64]
with open('/home/user/tokens.txt', 'w') as f:
    for length in lengths:
        token = base64.b64encode(secrets.token_bytes(length)).decode('ascii')
        f.write(token + '\n')
PY_EOF

    rm -f /home/user/audit_trail.log
    (cd /home/user && timeout 20s /tmp/audit_submission)
    python3 -m pytest /tmp/test_final_state.py -x --tb=short

    # Restore the required final state and verify it again.
    cp "$original_tokens" /home/user/tokens.txt
    rm -f /home/user/audit_trail.log
    (cd /home/user && timeout 20s /tmp/audit_submission)
    python3 -m pytest /tmp/test_final_state.py -x --tb=short
); then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
