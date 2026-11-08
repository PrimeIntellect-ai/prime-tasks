#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import subprocess
import base64
import random
import secrets
import uuid


def _base64url_decode(data: str) -> bytes:
    """Helper to decode base64url encoded strings (adding padding if necessary)."""
    padding = '=' * (4 - (len(data) % 4))
    return base64.urlsafe_b64decode(data + padding)


def _base64url_encode(data: bytes) -> str:
    """Helper to encode to base64url without padding."""
    return base64.urlsafe_b64encode(data).decode('utf-8').rstrip('=')


def _make_token(alg: str, user: str = "fixture_user") -> str:
    header = {"alg": alg, "typ": "JWT"}
    payload = {"user": user, "role": "admin"}
    header_enc = _base64url_encode(json.dumps(header, separators=(',', ':')).encode('utf-8'))
    payload_enc = _base64url_encode(json.dumps(payload, separators=(',', ':')).encode('utf-8'))
    signature = "" if alg.lower() == "none" else "test_signature"
    return f"{header_enc}.{payload_enc}.{signature}"


def test_block_ips_script_exists_and_executable():
    """Validates that block_ips.sh exists and is executable."""
    script_path = "/home/user/block_ips.sh"
    assert os.path.isfile(script_path), f"Missing script: {script_path}"
    assert os.access(script_path, os.X_OK), f"Script is not executable: {script_path}"


def test_craft_jwt_script_exists_and_executable():
    """Validates that craft_jwt.sh exists and is executable."""
    script_path = "/home/user/craft_jwt.sh"
    assert os.path.isfile(script_path), f"Missing script: {script_path}"
    assert os.access(script_path, os.X_OK), f"Script is not executable: {script_path}"


def test_block_ips_generates_correct_policy():
    """
    Executes block_ips.sh, derives the expected malicious IPs from the log file,
    and verifies that deny_policy.json exactly matches the derived expected state.
    """
    script_path = "/home/user/block_ips.sh"
    log_path = "/home/user/gateway.log"
    policy_path = "/home/user/deny_policy.json"

    if os.path.exists(policy_path):
        os.remove(policy_path)

    result = subprocess.run([script_path], capture_output=True, text=True)
    assert result.returncode == 0, f"Script {script_path} failed with exit code {result.returncode}. Stderr: {result.stderr}"

    assert os.path.isfile(policy_path), f"Script did not generate the expected policy file at {policy_path}"

    expected_ips = set()
    with open(log_path, 'r') as f:
        for line in f:
            if not line.strip():
                continue
            try:
                entry = json.loads(line)
                if entry.get("status") == 200:
                    auth_header = entry.get("auth_header", "")
                    if auth_header.startswith("Bearer "):
                        token = auth_header.split(" ")[1]
                        parts = token.split(".")
                        if len(parts) >= 1:
                            header_b64 = parts[0]
                            header_json = json.loads(_base64url_decode(header_b64).decode('utf-8'))
                            if header_json.get("alg", "").lower() == "none":
                                expected_ips.add(entry.get("ip"))
            except Exception:
                continue

    expected_ips_sorted = sorted(list(expected_ips))

    with open(policy_path, 'r') as f:
        try:
            policy_data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"Generated file {policy_path} is not valid JSON."

    assert "blocked_ips" in policy_data, f"Generated policy missing 'blocked_ips' key. Found keys: {list(policy_data.keys())}"

    actual_ips = policy_data["blocked_ips"]
    assert isinstance(actual_ips, list), "'blocked_ips' must be a JSON array."

    assert actual_ips == expected_ips_sorted, f"Blocked IPs do not match expected. Expected: {expected_ips_sorted}, Got: {actual_ips}"


def test_block_ips_parses_changed_log_fixture():
    """Checks behavior against an unpredictable replacement log, not fixed IPs."""
    script_path = "/home/user/block_ips.sh"
    log_path = "/home/user/gateway.log"
    policy_path = "/home/user/deny_policy.json"

    with open(log_path, "rb") as f:
        original_log = f.read()
    policy_existed = os.path.exists(policy_path)
    original_policy = None
    if policy_existed:
        with open(policy_path, "rb") as f:
            original_policy = f.read()

    generated_ips = set()
    while len(generated_ips) < 5:
        generated_ips.add(
            f"10.{secrets.randbelow(256)}.{secrets.randbelow(256)}.{secrets.randbelow(254) + 1}"
        )
    malicious = list(generated_ips)[:3]
    rejected_none = list(generated_ips)[3]
    successful_signed = list(generated_ips)[4]

    entries = []
    for ip, alg in zip(malicious, ["none", "None", "NONE"]):
        entries.append({
            "timestamp": "2026-01-01T00:00:00Z",
            "ip": ip,
            "path": "/dynamic/admin",
            "auth_header": "Bearer " + _make_token(alg, uuid.uuid4().hex),
            "status": 200,
        })
    entries.append({
        "timestamp": "2026-01-01T00:00:01Z",
        "ip": malicious[0],
        "path": "/dynamic/duplicate",
        "auth_header": "Bearer " + _make_token("NoNe", uuid.uuid4().hex),
        "status": 200,
    })
    entries.append({
        "timestamp": "2026-01-01T00:00:02Z",
        "ip": rejected_none,
        "path": "/dynamic/rejected",
        "auth_header": "Bearer " + _make_token("none", uuid.uuid4().hex),
        "status": 401,
    })
    entries.append({
        "timestamp": "2026-01-01T00:00:03Z",
        "ip": successful_signed,
        "path": "/dynamic/signed",
        "auth_header": "Bearer " + _make_token("HS256", uuid.uuid4().hex),
        "status": 200,
    })
    random.SystemRandom().shuffle(entries)

    try:
        with open(log_path, "w") as f:
            for entry in entries:
                f.write(json.dumps(entry) + "\n")
        if os.path.exists(policy_path):
            os.remove(policy_path)

        result = subprocess.run([script_path], capture_output=True, text=True)
        assert result.returncode == 0, f"Script failed on changed log with exit code {result.returncode}. Stderr: {result.stderr}"
        assert os.path.isfile(policy_path), f"Script did not generate {policy_path} for the changed log"

        with open(policy_path, "r") as f:
            policy_data = json.load(f)
        assert "blocked_ips" in policy_data, "Generated policy missing 'blocked_ips' key"
        assert isinstance(policy_data["blocked_ips"], list), "'blocked_ips' must be a JSON array"
        assert policy_data["blocked_ips"] == sorted(malicious), (
            f"Script did not derive IPs from the changed log. Expected {sorted(malicious)}, "
            f"got {policy_data['blocked_ips']}"
        )
    finally:
        with open(log_path, "wb") as f:
            f.write(original_log)
        if policy_existed:
            with open(policy_path, "wb") as f:
                f.write(original_policy)
        elif os.path.exists(policy_path):
            os.remove(policy_path)


def test_craft_jwt_output():
    """
    Executes craft_jwt.sh with a test username and verifies the generated JWT
    matches the exact expected Base64Url encoded structure.
    """
    script_path = "/home/user/craft_jwt.sh"
    test_user = "test_validator_user"

    result = subprocess.run([script_path, test_user], capture_output=True, text=True)
    assert result.returncode == 0, f"Script {script_path} failed with exit code {result.returncode}. Stderr: {result.stderr}"

    output_token = result.stdout.strip()

    header = {"alg": "none", "typ": "JWT"}
    payload = {"user": test_user, "role": "admin"}

    header_enc = _base64url_encode(json.dumps(header, separators=(',', ':')).encode('utf-8'))
    payload_enc = _base64url_encode(json.dumps(payload, separators=(',', ':')).encode('utf-8'))

    expected_token = f"{header_enc}.{payload_enc}."

    assert output_token == expected_token, f"Crafted JWT is incorrect.\nExpected: {expected_token}\nGot:      {output_token}"


def test_craft_jwt_uses_each_supplied_username():
    """Exercises the script with unpredictable usernames to ensure it uses its argument."""
    script_path = "/home/user/craft_jwt.sh"
    users = [f"dynamic_{uuid.uuid4().hex}", f"account_{uuid.uuid4().hex}"]

    for test_user in users:
        result = subprocess.run([script_path, test_user], capture_output=True, text=True)
        assert result.returncode == 0, f"Script failed for username {test_user}. Stderr: {result.stderr}"

        header = {"alg": "none", "typ": "JWT"}
        payload = {"user": test_user, "role": "admin"}
        header_enc = _base64url_encode(json.dumps(header, separators=(',', ':')).encode('utf-8'))
        payload_enc = _base64url_encode(json.dumps(payload, separators=(',', ':')).encode('utf-8'))
        expected_token = f"{header_enc}.{payload_enc}."

        assert result.stdout.strip() == expected_token, (
            f"Crafted JWT does not reflect supplied username {test_user}. "
            f"Expected {expected_token}, got {result.stdout.strip()}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
