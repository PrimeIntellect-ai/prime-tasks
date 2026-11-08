#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import secrets
import subprocess
import urllib.request
import pytest

AUDIT_FILE = "/home/user/audit_trail.json"


def load_audit():
    assert os.path.isfile(AUDIT_FILE), f"File {AUDIT_FILE} does not exist. The audit trail was not generated."
    with open(AUDIT_FILE, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {AUDIT_FILE} is not valid JSON.")


def test_audit_trail_exists_and_valid():
    data = load_audit()
    expected_keys = {"salt", "cracked_password", "auth_status_code", "auth_response_body"}
    missing_keys = expected_keys - set(data.keys())
    assert not missing_keys, f"Audit trail is missing keys: {missing_keys}"
    assert set(data.keys()) == expected_keys, f"Audit trail has unexpected keys: {set(data.keys()) - expected_keys}"

    assert data["salt"] == "S4lTy_B3v3r4g3!!", f"Incorrect salt extracted: {data['salt']}"
    assert data["cracked_password"] == "bluebird99", f"Incorrect cracked password: {data['cracked_password']}"
    assert data["auth_status_code"] == 200, f"Incorrect auth status code: {data['auth_status_code']}"
    assert data["auth_response_body"] == '{"status":"success","token":"AUTH_TOKEN_9932"}', f"Incorrect auth response body: {data['auth_response_body']}"


def test_live_authentication_matches_audit():
    data = load_audit()
    payload = json.dumps({
        "username": "compliance_admin",
        "password": data["cracked_password"],
    }).encode("utf-8")
    request = urllib.request.Request(
        "http://127.0.0.1:9090/login",
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=5) as response:
        status = response.status
        body = response.read().decode("utf-8")
    assert status == data["auth_status_code"]
    assert body == data["auth_response_body"]


def test_cracker_cpp_exists_and_works_on_derived_input():
    cpp_file = "/home/user/cracker.cpp"
    assert os.path.isfile(cpp_file), f"File {cpp_file} does not exist. The C++ cracker program was not written."

    executable = "/tmp/cracker_verify"
    compile_result = subprocess.run(
        ["g++", "-std=c++17", cpp_file, "-o", executable, "-lssl", "-lcrypto"],
        text=True,
        capture_output=True,
        timeout=30,
    )
    assert compile_result.returncode == 0, f"cracker.cpp did not compile:\n{compile_result.stderr}"

    wordlist_path = "/home/user/wordlist.txt"
    db_path = "/home/user/db.txt"
    with open(wordlist_path, "rb") as f:
        original_wordlist = f.read()
    with open(db_path, "rb") as f:
        original_db = f.read()

    candidate = "probe_" + secrets.token_hex(8)
    salt = "S4lTy_B3v3r4g3!!"
    target_hash = hashlib.sha256((candidate + salt).encode()).hexdigest()
    decoys = ["wrong_" + secrets.token_hex(6) for _ in range(3)]

    try:
        with open(wordlist_path, "w") as f:
            f.write("\n".join([decoys[0], candidate, decoys[1], decoys[2]]) + "\n")
        with open(db_path, "w") as f:
            f.write(f"user1:{'0' * 64}\n")
            f.write(f"compliance_admin:{target_hash}\n")
            f.write(f"guest:{'f' * 64}\n")

        run_result = subprocess.run(
            ["runuser", "-u", "user", "--", executable],
            cwd="/home/user",
            text=True,
            capture_output=True,
            timeout=20,
        )
        output = run_result.stdout + run_result.stderr
        assert run_result.returncode == 0, f"Compiled cracker failed:\n{output}"
        assert candidate in output, "Compiled cracker did not find the password from the supplied wordlist and database."
    finally:
        with open(wordlist_path, "wb") as f:
            f.write(original_wordlist)
        with open(db_path, "wb") as f:
            f.write(original_db)
        if os.path.exists(executable):
            os.remove(executable)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
