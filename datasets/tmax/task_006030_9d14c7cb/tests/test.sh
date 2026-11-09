#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import hashlib
import importlib.util
import json
import os
import sqlite3
import subprocess

import pytest

BASE_DIR = "/home/user/incident_response"


def test_phase1_cracked_passwords():
    """Verify Phase 1: submitted plaintexts match the supplied hashes."""
    output_file = os.path.join(BASE_DIR, "cracked_passwords.json")
    hashes_file = os.path.join(BASE_DIR, "admin_hashes.txt")
    assert os.path.isfile(output_file), f"Phase 1 output file is missing: {output_file}"

    with open(output_file, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {output_file} does not contain valid JSON.")

    expected_hashes = {}
    with open(hashes_file, "r") as f:
        for line in f:
            line = line.strip()
            if line:
                username, digest = line.split(":", 1)
                expected_hashes[username] = digest.lower()

    assert isinstance(data, dict), "Cracked passwords output must be a JSON object."
    assert set(data) == set(expected_hashes), (
        f"Cracked passwords must contain exactly these users: {set(expected_hashes)}"
    )
    for username, expected_digest in expected_hashes.items():
        password = data[username]
        assert isinstance(password, str), f"Password for {username} must be a string."
        actual_digest = hashlib.sha256(password.encode("utf-8")).hexdigest()
        assert actual_digest == expected_digest, f"Incorrect cracked password for {username}."


def test_phase2_app_patched(tmp_path):
    """Verify Phase 2 statically and by exercising the Flask login endpoint."""
    app_path = os.path.join(BASE_DIR, "auth_service", "app.py")
    assert os.path.isfile(app_path), f"Phase 2 app.py file is missing: {app_path}"

    with open(app_path, "r") as f:
        source = f.read()

    tree = ast.parse(source)
    execute_calls = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Call):
            if isinstance(node.func, ast.Attribute) and node.func.attr == "execute":
                execute_calls.append(node)

    assert len(execute_calls) > 0, "No cursor.execute() found in app.py"

    for call in execute_calls:
        if len(call.args) > 0:
            query_arg = call.args[0]
            assert not isinstance(query_arg, ast.JoinedStr), "SQL Injection vulnerability still present: f-string used in cursor.execute()"
            assert not isinstance(query_arg, ast.BinOp), "SQL Injection vulnerability still present: string formatting used in cursor.execute()"
            assert not (isinstance(query_arg, ast.Call) and isinstance(query_arg.func, ast.Attribute) and query_arg.func.attr == "format"), "SQL Injection vulnerability still present: .format() used in cursor.execute()"

    assert any(len(call.args) >= 2 or any(k.arg == "parameters" for k in call.keywords) for call in execute_calls), \
        "SQL queries must pass values separately to sqlite3 cursor.execute()."

    # Preserve the original source-level redirect assertions and additionally
    # prove that the validation is effective at runtime.
    assert "startswith" in source and "'/'" in source, "Open Redirect vulnerability still present: missing check for relative path (startswith('/'))"
    assert "'//'" in source, "Open Redirect vulnerability still present: missing check to prevent protocol-relative URLs (//)"

    db_path = tmp_path / "users.db"
    conn = sqlite3.connect(str(db_path))
    conn.execute("CREATE TABLE users (username TEXT, password TEXT)")
    conn.execute("INSERT INTO users (username, password) VALUES (?, ?)", ("validuser", "validpass"))
    conn.commit()
    conn.close()

    spec = importlib.util.spec_from_file_location("incident_auth_app", app_path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert hasattr(module, "app"), "app.py does not define the Flask application."
    module.get_db = lambda: sqlite3.connect(str(db_path))
    module.app.config.update(TESTING=True)
    client = module.app.test_client()

    # A genuine login must still work and preserve an allowed relative target.
    response = client.post(
        "/login",
        query_string={"next": "/dashboard"},
        data={"username": "validuser", "password": "validpass"},
    )
    assert response.status_code in range(300, 400), "Valid credentials no longer produce a redirect."
    assert response.headers.get("Location") == "/dashboard", "A valid relative next path was not honored."

    # Both username and password injection attempts must fail authentication.
    for username, password in [
        ("' OR 1=1 --", "wrong"),
        ("validuser", "' OR 1=1 --"),
    ]:
        response = client.post(
            "/login",
            query_string={"next": "/dashboard"},
            data={"username": username, "password": password},
        )
        assert response.status_code == 401, "SQL injection payload authenticated successfully."

    # Authenticated requests must never redirect to a disallowed next value.
    for unsafe_next in ["//evil.example/path", "https://evil.example/path", "/safe//evil"]:
        response = client.post(
            "/login",
            query_string={"next": unsafe_next},
            data={"username": "validuser", "password": "validpass"},
        )
        assert response.status_code < 500, "Unsafe next value caused an application error."
        if response.status_code in range(300, 400):
            location = response.headers.get("Location", "")
            assert location.startswith("/"), f"Open redirect allowed absolute target: {location}"
            assert "//" not in location, f"Open redirect allowed disallowed target: {location}"


def test_phase3_token_rotated():
    """Verify Phase 3: Master token is correctly re-encrypted with new key and IV."""
    rotated_token_path = os.path.join(BASE_DIR, "tokens", "master_token_rotated.enc")
    new_key_path = os.path.join(BASE_DIR, "keys", "new_key.bin")
    new_iv_path = os.path.join(BASE_DIR, "keys", "new_iv.bin")

    assert os.path.isfile(rotated_token_path), f"Phase 3 output file is missing: {rotated_token_path}"
    assert os.path.isfile(new_key_path), f"New key file is missing: {new_key_path}"
    assert os.path.isfile(new_iv_path), f"New IV file is missing: {new_iv_path}"

    with open(new_key_path, "rb") as f:
        new_key_hex = f.read().hex()
    with open(new_iv_path, "rb") as f:
        new_iv_hex = f.read().hex()

    cmd = [
        "openssl", "enc", "-d", "-aes-256-cbc",
        "-in", rotated_token_path,
        "-K", new_key_hex,
        "-iv", new_iv_hex,
    ]
    result = subprocess.run(cmd, capture_output=True)
    assert result.returncode == 0, f"Failed to decrypt rotated token. OpenSSL error: {result.stderr.decode()}"

    decrypted_token = result.stdout.decode("utf-8")
    expected_token = "SuperSecretMasterToken999"
    assert decrypted_token == expected_token, f"Decrypted token does not match expected value. Got: {decrypted_token}"


def test_phase4_invalid_cert_identified():
    """Verify Phase 4: Invalid certificate Common Name is correctly identified."""
    output_file = os.path.join(BASE_DIR, "invalid_cert_cn.txt")
    assert os.path.isfile(output_file), f"Phase 4 output file is missing: {output_file}"

    with open(output_file, "r") as f:
        cn = f.read().strip()

    expected_cn = "Compromised-Intermediate-CA"
    assert cn == expected_cn, f"Invalid certificate CN incorrect. Expected '{expected_cn}', got '{cn}'"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
