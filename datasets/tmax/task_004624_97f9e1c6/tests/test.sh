#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import secrets
import stat
import subprocess
import sys

from cryptography.fernet import Fernet


def test_auth_key_permissions():
    key_path = "/home/user/auth_key.key"
    assert os.path.exists(key_path), f"Missing file: {key_path}"

    st = os.stat(key_path)
    permissions = stat.S_IMODE(st.st_mode)
    assert permissions == 0o400, f"Expected permissions 0o400 on {key_path}, but got {oct(permissions)}"


def test_analyze_script_exists():
    script_path = "/home/user/analyze.py"
    assert os.path.exists(script_path), f"Missing script file: {script_path}"
    assert os.path.isfile(script_path), f"Not a file: {script_path}"


def test_investigation_result_log():
    log_path = "/home/user/investigation_result.log"
    assert os.path.exists(log_path), f"Missing log file: {log_path}"

    with open(log_path, "r") as f:
        content = f.read().strip()

    expected_endpoint = "/api/v3/hidden_command_c2_991x"
    assert content == expected_endpoint, f"Expected log content '{expected_endpoint}', but got '{content}'"
    with open(log_path, "rb") as f:
        assert f.read() == expected_endpoint.encode(), "Result log contains extra text or formatting"


def test_analyze_script_decrypts_and_validates_dynamic_payloads():
    script_path = "/home/user/analyze.py"
    key_path = "/home/user/auth_key.key"
    token_path = "/home/user/intercepted_token.txt"
    log_path = "/home/user/investigation_result.log"

    # Rotate the key so the script must read the key file rather than embed the
    # setup-time key, and use an unpredictable endpoint.
    key = Fernet.generate_key()
    with open(key_path, "wb") as f:
        f.write(key)
    os.chmod(key_path, 0o400)
    cipher = Fernet(key)

    endpoint = "/api/verify/" + secrets.token_hex(20)
    checksum = hashlib.sha256(endpoint.encode()).hexdigest()
    payload = {
        "user": "dynamic_user",
        "role": "engineer",
        "next_endpoint": endpoint,
        "checksum": checksum,
    }
    with open(token_path, "wb") as f:
        f.write(cipher.encrypt(json.dumps(payload).encode()))

    result = subprocess.run(
        [sys.executable, script_path],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )
    assert result.returncode == 0, result.stderr.decode(errors="replace")
    assert os.path.exists(log_path), f"Missing log file: {log_path}"
    with open(log_path, "rb") as f:
        assert f.read() == endpoint.encode(), "Script did not write the dynamically decrypted endpoint exactly"

    bad_checksum = ("0" if checksum[0] != "0" else "1") + checksum[1:]
    payload["checksum"] = bad_checksum
    with open(token_path, "wb") as f:
        f.write(cipher.encrypt(json.dumps(payload).encode()))

    result = subprocess.run(
        [sys.executable, script_path],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )
    assert result.returncode == 0, result.stderr.decode(errors="replace")
    with open(log_path, "rb") as f:
        assert f.read() == b"CORRUPTED", "Script did not reject a payload with an invalid checksum exactly"

    permissions = stat.S_IMODE(os.stat(key_path).st_mode)
    assert permissions == 0o400, f"Expected permissions 0o400 on {key_path}, but got {oct(permissions)}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
