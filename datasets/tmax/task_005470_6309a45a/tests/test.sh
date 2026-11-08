#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import json
import base64
import hmac
import hashlib
import subprocess
from collections import defaultdict, deque
from datetime import datetime
import pytest

SUMMARY_PATH = "/home/user/rotation_summary.json"
KEYS_DIR = "/home/user/keys"
SECRET_PATH = "/home/user/master.secret"
AUTH_LOG_PATH = "/home/user/auth.log"
LOG_RE = re.compile(r"^\[(?P<timestamp>[^]]+)\] user=(?P<user>\S+) ip=(?P<ip>\S+) event=(?P<event>FAILED|SUCCESS)$")


def base64url_decode(input_str):
    rem = len(input_str) % 4
    if rem > 0:
        input_str += '=' * (4 - rem)
    return base64.urlsafe_b64decode(input_str)


def base64url_encode(input_bytes):
    return base64.urlsafe_b64encode(input_bytes).decode('utf-8').rstrip('=')


def detect_compromised_users():
    assert os.path.isfile(AUTH_LOG_PATH), f"Authentication log missing at {AUTH_LOG_PATH}"
    recent_failures = defaultdict(deque)
    compromised = set()

    with open(AUTH_LOG_PATH, "r") as f:
        for line_number, raw_line in enumerate(f, 1):
            line = raw_line.strip()
            if not line:
                continue
            match = LOG_RE.fullmatch(line)
            assert match is not None, f"Malformed authentication log entry on line {line_number}"
            timestamp = datetime.strptime(match.group("timestamp"), "%Y-%m-%d %H:%M:%S")
            user = match.group("user")
            ip = match.group("ip")
            event = match.group("event")
            key = (user, ip)
            failures = recent_failures[key]

            while failures and (timestamp - failures[0]).total_seconds() > 60:
                failures.popleft()

            if event == "FAILED":
                failures.append(timestamp)
            else:
                if len(failures) >= 3:
                    compromised.add(user)
                failures.clear()

    return compromised


def expected_users():
    users = detect_compromised_users()
    # Preserve the original fixture assertion and detect attempts to rewrite the input.
    assert users == {"bob", "david"}, f"Authentication log produced unexpected compromised users: {users}"
    return users


def test_summary_exists_and_format():
    assert os.path.isfile(SUMMARY_PATH), f"Summary file missing at {SUMMARY_PATH}"

    with open(SUMMARY_PATH, "r") as f:
        try:
            summary = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("Summary file is not valid JSON")

    expected = expected_users()
    actual_users = set(summary.keys())
    assert actual_users == expected, f"Expected compromised users {expected}, found {actual_users}"

    for user in expected:
        assert "pub_key" in summary[user], f"Missing pub_key for {user}"
        assert "token" in summary[user], f"Missing token for {user}"


def test_ssh_keys_created_and_match():
    with open(SUMMARY_PATH, "r") as f:
        summary = json.load(f)

    for user in expected_users():
        pub_key_path = os.path.join(KEYS_DIR, f"{user}_id_ed25519.pub")
        priv_key_path = os.path.join(KEYS_DIR, f"{user}_id_ed25519")

        assert os.path.isfile(pub_key_path), f"Public key missing at {pub_key_path}"
        assert os.path.isfile(priv_key_path), f"Private key missing at {priv_key_path}"

        with open(pub_key_path, "r") as f:
            actual_pub_key = f.read().strip()

        assert summary[user]["pub_key"].strip() == actual_pub_key, f"pub_key in summary does not match file for {user}"

        validation = subprocess.run(
            ["ssh-keygen", "-l", "-f", pub_key_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
        )
        assert validation.returncode == 0, f"Invalid SSH public key for {user}: {validation.stderr.strip()}"

        derived = subprocess.run(
            ["ssh-keygen", "-y", "-P", "", "-f", priv_key_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
        )
        assert derived.returncode == 0, f"Private key for {user} is invalid or passphrase-protected: {derived.stderr.strip()}"

        public_fields = actual_pub_key.split()
        derived_fields = derived.stdout.strip().split()
        assert len(public_fields) >= 2, f"Malformed public key for {user}"
        assert len(derived_fields) >= 2, f"Could not derive public key for {user}"
        assert public_fields[0] == "ssh-ed25519", f"Key for {user} is not Ed25519"
        assert derived_fields[0] == "ssh-ed25519", f"Private key for {user} is not Ed25519"
        assert public_fields[:2] == derived_fields[:2], f"Private and public keys do not form a pair for {user}"


def test_jwt_tokens_valid():
    assert os.path.isfile(SECRET_PATH), "Master secret file missing"
    with open(SECRET_PATH, "r") as f:
        secret = f.read().strip().encode('utf-8')

    with open(SUMMARY_PATH, "r") as f:
        summary = json.load(f)

    for user in expected_users():
        token = summary[user]["token"]
        parts = token.split(".")
        assert len(parts) == 3, f"Token for {user} is not in 3 parts"

        header_b64, payload_b64, sig_b64 = parts

        header = json.loads(base64url_decode(header_b64).decode('utf-8'))
        payload = json.loads(base64url_decode(payload_b64).decode('utf-8'))

        assert header.get("alg") == "HS256"
        assert header.get("typ") == "JWT"

        assert payload.get("user") == user
        assert payload.get("action") == "key_rotation"

        msg = f"{header_b64}.{payload_b64}".encode('utf-8')
        expected_sig = base64url_encode(hmac.new(secret, msg, hashlib.sha256).digest())

        assert sig_b64 == expected_sig, f"Invalid token signature for {user}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
