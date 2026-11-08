#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import hashlib
import hmac
import json
import os
import secrets
import stat
import subprocess
import tempfile
import pytest


def _run(cmd, **kwargs):
    return subprocess.run(cmd, capture_output=True, text=True, **kwargs)


def _public_from_private(path):
    with open(path, "rb") as src, tempfile.NamedTemporaryFile(delete=False) as tmp:
        tmp.write(src.read())
        tmp_path = tmp.name
    try:
        os.chmod(tmp_path, 0o600)
        result = _run(["ssh-keygen", "-y", "-f", tmp_path])
        assert result.returncode == 0, f"{path} is not a valid private SSH key: {result.stderr}"
        return result.stdout.strip().split()[:2]
    finally:
        os.unlink(tmp_path)


def test_ssh_keys_quarantined_and_fingerprints():
    quarantine_dir = "/home/user/quarantine_keys"
    assert os.path.isdir(quarantine_dir), f"Quarantine directory {quarantine_dir} is missing."

    secure_keys = ["id_rsa_4096", "id_ecdsa_256"]
    insecure_keys = ["id_rsa_1024", "id_ed25519_open"]
    secure_keys_file = "/home/user/secure_keys.txt"

    assert os.path.isfile(secure_keys_file), f"{secure_keys_file} is missing."

    with open(secure_keys_file, "r") as f:
        content = f.read().strip()

    expected_fingerprint_lines = []
    for key in secure_keys:
        private_path = f"/home/user/ssh_audit/{key}"
        assert os.path.isfile(private_path), f"Secure private key {private_path} is missing."

        pub_key_path = f"/home/user/ssh_audit/{key}.pub"
        if not os.path.exists(pub_key_path):
            pub_key_path = private_path

        try:
            result = subprocess.run(
                ["ssh-keygen", "-l", "-f", pub_key_path],
                capture_output=True, text=True, check=True
            )
            fingerprint = result.stdout.strip()
            expected_fingerprint_lines.append(fingerprint)
            hash_part = fingerprint.split()[1]
            assert hash_part in content, f"Fingerprint for {key} ({hash_part}) not found in {secure_keys_file}."
        except subprocess.CalledProcessError:
            pytest.fail(f"Could not compute fingerprint for {pub_key_path}")

    actual_lines = [line.strip() for line in content.splitlines() if line.strip()]
    assert len(actual_lines) == len(expected_fingerprint_lines), \
        f"Expected exactly one fingerprint per secure key, found: {actual_lines}"
    assert set(actual_lines) == set(expected_fingerprint_lines), \
        f"secure_keys.txt does not contain the exact ssh-keygen fingerprint lines. Expected {expected_fingerprint_lines}, found {actual_lines}"

    for key in insecure_keys:
        original = f"/home/user/ssh_audit/{key}"
        quarantined = f"{quarantine_dir}/{key}"
        public_key = f"/home/user/ssh_audit/{key}.pub"

        assert not os.path.exists(original), f"Insecure private key {original} was not removed from ssh_audit."
        assert os.path.isfile(quarantined), f"Insecure private key {key} is missing from quarantine."
        assert os.path.isfile(public_key), f"Public key needed to identify {key} is missing."

        derived_public = _public_from_private(quarantined)
        with open(public_key, "r") as f:
            expected_public = f.read().strip().split()[:2]
        assert derived_public == expected_public, \
            f"Quarantined file {quarantined} is not the private key corresponding to {public_key}."

    rsa_result = _run(["ssh-keygen", "-l", "-f", "/home/user/ssh_audit/id_rsa_1024.pub"])
    assert rsa_result.returncode == 0
    assert int(rsa_result.stdout.split()[0]) < 2048, "The quarantined RSA key is not an insecure short RSA key."


def test_artifacts_corrupted_files():
    corrupted_file = "/home/user/corrupted_files.txt"
    assert os.path.isfile(corrupted_file), f"{corrupted_file} is missing."

    with open(corrupted_file, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected = {"lib_v1.bin", "data_v1.bin"}
    actual = set(lines)

    assert expected.issubset(actual), f"Expected corrupted files {expected} not fully found in {corrupted_file}. Found: {actual}"
    assert len(actual) == 2, f"Expected exactly 2 corrupted files, found {len(actual)}: {actual}"


def _run_instrumented_login(directory):
    launcher = r'''
import hmac
import runpy
import sys
calls = [0]
original = hmac.compare_digest
def monitored(a, b):
    calls[0] += 1
    return original(a, b)
hmac.compare_digest = monitored
try:
    runpy.run_path("login_check.py", run_name="__main__")
finally:
    print("__COMPARE_CALLS__=" + str(calls[0]), file=sys.stderr)
'''
    return _run(["python3", "-c", launcher], cwd=directory)


def test_auth_script_and_user():
    valid_user_file = "/home/user/valid_user.txt"
    assert os.path.isfile(valid_user_file), f"{valid_user_file} is missing."

    with open(valid_user_file, "r") as f:
        user = f.read().strip()

    assert user == "charlie", f"Expected valid user 'charlie', found '{user}'."

    secret_key_path = "/home/user/auth/secret.key"
    assert os.path.isfile(secret_key_path), f"{secret_key_path} is missing."

    st = os.stat(secret_key_path)
    perms = stat.S_IMODE(st.st_mode)
    assert perms == 0o600, f"Expected permissions 0600 on {secret_key_path}, got {oct(perms)}"

    login_check_path = "/home/user/auth/login_check.py"
    assert os.path.isfile(login_check_path), f"{login_check_path} is missing."

    with open(login_check_path, "r") as f:
        script_content = f.read()

    assert "hmac.compare_digest" in script_content, f"hmac.compare_digest not found in {login_check_path}"
    assert "hashlib.sha256" in script_content, f"hashlib.sha256 not found in {login_check_path}"

    tree = ast.parse(script_content, filename=login_check_path)
    calls = [node for node in ast.walk(tree) if isinstance(node, ast.Call)]
    assert any(isinstance(node.func, ast.Attribute)
               and isinstance(node.func.value, ast.Name)
               and node.func.value.id == "hmac"
               and node.func.attr == "compare_digest" for node in calls), \
        "login_check.py does not execute a call to hmac.compare_digest."
    assert any(isinstance(node.func, ast.Attribute)
               and isinstance(node.func.value, ast.Name)
               and node.func.value.id == "hashlib"
               and node.func.attr == "sha256" for node in calls), \
        "login_check.py does not use hashlib.sha256 in executable code."

    original_run = _run(["python3", "login_check.py"], cwd="/home/user/auth")
    assert original_run.returncode == 0, f"login_check.py failed: {original_run.stderr}"
    original_users = [line.strip() for line in original_run.stdout.splitlines() if line.strip()]
    assert original_users == [user], \
        f"valid_user.txt does not match the script's single valid result: {original_users}"

    with tempfile.TemporaryDirectory() as temp_dir:
        with open(os.path.join(temp_dir, "login_check.py"), "w") as f:
            f.write(script_content)

        secret = secrets.token_bytes(32)
        secret_text = secret.hex()
        users = ["audit_" + secrets.token_hex(8) for _ in range(4)]
        payloads = ["payload_" + secrets.token_hex(12) for _ in range(4)]
        valid_index = secrets.randbelow(4)
        requests = []
        for index, (test_user, payload) in enumerate(zip(users, payloads)):
            if index == valid_index:
                signature = hmac.new(secret_text.encode(), payload.encode(), hashlib.sha256).hexdigest()
            else:
                signature = hmac.new(secret_text.encode(), payload.encode(), hashlib.md5).hexdigest()
            requests.append({"user": test_user, "payload": payload, "signature": signature})

        secret_path = os.path.join(temp_dir, "secret.key")
        with open(secret_path, "w") as f:
            f.write(secret_text + "\n")
        os.chmod(secret_path, 0o600)
        with open(os.path.join(temp_dir, "requests.json"), "w") as f:
            json.dump(requests, f)

        result = _run_instrumented_login(temp_dir)
        assert result.returncode == 0, f"login_check.py failed on independent requests: {result.stderr}"
        output_users = [line.strip() for line in result.stdout.splitlines() if line.strip()]
        assert output_users == [users[valid_index]], \
            f"login_check.py did not identify the independently generated SHA256 request: {output_users}"

        marker = [line for line in result.stderr.splitlines() if line.startswith("__COMPARE_CALLS__=")]
        assert marker, "Could not verify that hmac.compare_digest was called at runtime."
        assert int(marker[-1].split("=", 1)[1]) > 0, \
            "login_check.py did not call hmac.compare_digest at runtime."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
