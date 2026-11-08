#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import json
import os
import stat
import subprocess
import uuid

import pytest
from cryptography.fernet import Fernet

LOG_PATH = "/home/user/access.log"
KEY_PATH = "/home/user/rotation_key.key"
ENC_PATH = "/home/user/revocation_list.enc"
SCRIPT_PATH = "/home/user/process_logs.py"


def encode_jwt(header, payload, sig=""):
    h = base64.urlsafe_b64encode(json.dumps(header).encode()).decode().rstrip("=")
    p = base64.urlsafe_b64encode(json.dumps(payload).encode()).decode().rstrip("=")
    return f"{h}.{p}.{sig}" if sig else f"{h}.{p}."


def original_log_bytes():
    logs = [
        {
            "method": "GET",
            "path": "/api/data",
            "headers": {
                "Authorization": "Bearer " + encode_jwt({"alg": "HS256", "typ": "JWT"}, {"username": "alice"}, "fakesig123"),
                "User-Agent": "Mozilla/5.0",
            },
        },
        {
            "method": "POST",
            "path": "/api/admin",
            "headers": {
                "Authorization": "Bearer " + encode_jwt({"alg": "none", "typ": "JWT"}, {"username": "sysadmin"}),
                "User-Agent": "curl/7.68.0",
            },
        },
        {
            "method": "GET",
            "path": "/api/reports",
            "headers": {
                "Authorization": "Bearer " + encode_jwt({"alg": "RS256", "typ": "JWT"}, {"username": "bob"}, "fakesig456"),
                "User-Agent": "Mozilla/5.0",
            },
        },
        {
            "method": "DELETE",
            "path": "/api/users/1",
            "headers": {
                "Authorization": "Bearer " + encode_jwt({"alg": "None", "typ": "JWT"}, {"username": "db_service"}),
                "User-Agent": "python-requests/2.25.1",
            },
        },
        {
            "method": "POST",
            "path": "/api/admin",
            "headers": {
                "Authorization": "Bearer " + encode_jwt({"alg": "NONE", "typ": "JWT"}, {"username": "sysadmin"}),
                "User-Agent": "curl/7.68.0",
            },
        },
    ]
    return b"".join((json.dumps(entry) + "\n").encode() for entry in logs)


def recompute_users(log_path):
    compromised_users = set()
    with open(log_path, "r") as f:
        for line in f:
            if not line.strip():
                continue
            try:
                log_entry = json.loads(line)
                auth_header = log_entry.get("headers", {}).get("Authorization", "")
                if auth_header.startswith("Bearer "):
                    token = auth_header.split(" ")[1]
                    parts = token.split(".")
                    if len(parts) >= 2:
                        header_padded = parts[0] + "=" * ((4 - len(parts[0]) % 4) % 4)
                        header = json.loads(base64.urlsafe_b64decode(header_padded).decode("utf-8"))
                        alg = header.get("alg", "")
                        if alg.lower() == "none":
                            payload_padded = parts[1] + "=" * ((4 - len(parts[1]) % 4) % 4)
                            payload = json.loads(base64.urlsafe_b64decode(payload_padded).decode("utf-8"))
                            if "username" in payload:
                                compromised_users.add(payload["username"])
            except Exception:
                pass
    return ",".join(sorted(compromised_users))


def test_revocation_list_encrypted_correctly_and_script_processes_fresh_input():
    assert os.path.exists(LOG_PATH), f"Log file missing: {LOG_PATH}"
    assert os.path.exists(KEY_PATH), f"Key file missing: {KEY_PATH}"
    assert os.path.exists(ENC_PATH), f"Encrypted output file missing: {ENC_PATH}"
    assert os.path.exists(SCRIPT_PATH), f"Processing script missing: {SCRIPT_PATH}"
    assert stat.S_ISREG(os.stat(SCRIPT_PATH, follow_symlinks=False).st_mode), "Processing script must be a regular file"
    assert os.path.getsize(SCRIPT_PATH) > 0, "Processing script is empty"

    with open(LOG_PATH, "rb") as f:
        original_log = f.read()
    assert original_log == original_log_bytes(), "The supplied access.log was modified"

    expected_plaintext = recompute_users(LOG_PATH)
    assert expected_plaintext == "db_service,sysadmin"

    with open(KEY_PATH, "rb") as f:
        original_key = f.read()
    assert stat.S_ISREG(os.stat(KEY_PATH, follow_symlinks=False).st_mode), "Encryption key must be a regular file"
    try:
        original_fernet = Fernet(original_key)
    except Exception as e:
        pytest.fail(f"The supplied rotation key is not a valid Fernet key: {e}")

    with open(ENC_PATH, "rb") as f:
        original_encrypted = f.read()
    try:
        decrypted_data = original_fernet.decrypt(original_encrypted).decode("utf-8")
    except Exception as e:
        pytest.fail(f"Failed to decrypt {ENC_PATH}. Is it a valid Fernet token encrypted with the correct key? Error: {e}")
    assert decrypted_data == expected_plaintext, (
        f"Decrypted data does not match expected compromised users. "
        f"Expected '{expected_plaintext}', got '{decrypted_data}'"
    )

    # Exercise the submitted script after the agent has finished, using a fresh
    # key and unpredictable usernames so a precomputed output cannot pass.
    names = ["acct_" + uuid.uuid4().hex for _ in range(3)]
    expected_challenge = ",".join(sorted(names))
    challenge_logs = [
        {"headers": {"Authorization": "Bearer " + encode_jwt({"alg": "none"}, {"username": names[1]})}},
        {"headers": {"Authorization": "Bearer " + encode_jwt({"alg": "HS256"}, {"username": "safe_" + uuid.uuid4().hex}, "sig")}},
        {"headers": {"Authorization": "Bearer " + encode_jwt({"alg": "NONE"}, {"username": names[0]})}},
        {"headers": {"Authorization": "Bearer " + encode_jwt({"alg": "None"}, {"username": names[2]})}},
        {"headers": {"Authorization": "Bearer " + encode_jwt({"alg": "none"}, {"username": names[1]})}},
        {"headers": {"Authorization": "Bearer malformed.token"}},
        {"headers": {}},
    ]
    challenge_log = b"".join((json.dumps(entry) + "\n").encode() for entry in challenge_logs)
    challenge_key = Fernet.generate_key()

    try:
        with open(LOG_PATH, "wb") as f:
            f.write(challenge_log)
        with open(KEY_PATH, "wb") as f:
            f.write(challenge_key)
        if os.path.lexists(ENC_PATH):
            os.remove(ENC_PATH)

        result = subprocess.run(
            ["python3", SCRIPT_PATH],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=15,
        )
        assert result.returncode == 0, f"Processing script failed: {result.stderr}"
        assert os.path.isfile(ENC_PATH), "Processing script did not create revocation_list.enc"
        with open(ENC_PATH, "rb") as f:
            challenge_encrypted = f.read()
        try:
            challenge_plaintext = Fernet(challenge_key).decrypt(challenge_encrypted).decode("utf-8")
        except Exception as e:
            pytest.fail(f"Script output for fresh input is not a valid Fernet token using the supplied key: {e}")
        assert challenge_plaintext == expected_challenge, (
            f"Script processed fresh input incorrectly. Expected '{expected_challenge}', got '{challenge_plaintext}'"
        )
    finally:
        with open(LOG_PATH, "wb") as f:
            f.write(original_log)
        with open(KEY_PATH, "wb") as f:
            f.write(original_key)
        with open(ENC_PATH, "wb") as f:
            f.write(original_encrypted)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
