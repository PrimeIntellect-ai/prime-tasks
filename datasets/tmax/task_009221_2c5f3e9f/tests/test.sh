#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import socket
import sqlite3
import subprocess
import time
import urllib.error
import urllib.request


def test_cargo_compiles_successfully():
    """Test that the Rust project compiles successfully without errors."""
    app_dir = "/home/user/app"
    assert os.path.isdir(app_dir), f"Directory {app_dir} does not exist."

    result = subprocess.run(
        ["cargo", "check"],
        cwd=app_dir,
        capture_output=True,
        text=True
    )
    assert result.returncode == 0, f"Cargo check failed:\n{result.stderr}"

    # The instruction specifically requires a successful build, not only checking.
    result = subprocess.run(
        ["cargo", "build"],
        cwd=app_dir,
        capture_output=True,
        text=True
    )
    assert result.returncode == 0, f"Cargo build failed:\n{result.stderr}"
    executable = os.path.join(app_dir, "target", "debug", "secure-api")
    assert os.path.isfile(executable), "cargo build did not produce the secure-api executable."
    assert os.access(executable, os.X_OK), "The secure-api artifact is not executable."


def _post_registration(password):
    body = ('{"username":"verification-user","password":"%s"}' % password).encode()
    request = urllib.request.Request(
        "http://127.0.0.1:8080/api/register",
        data=body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=3) as response:
            return response.status
    except urllib.error.HTTPError as error:
        return error.code


def test_password_validation_logic():
    """Test both the source constraint and the running registration handler."""
    api_rs_path = "/home/user/app/src/api.rs"
    assert os.path.isfile(api_rs_path), f"File {api_rs_path} does not exist."

    with open(api_rs_path, "r") as f:
        content = f.read()

    # Preserve the original source assertion while also testing real behavior.
    assert re.search(r'<\s*12', content) or re.search(r'<=\s*11', content), \
        "Password length validation constraint was not updated to 12 characters."

    executable = "/home/user/app/target/debug/secure-api"
    assert os.path.isfile(executable) and os.access(executable, os.X_OK), \
        "The built secure-api executable is missing."

    process = subprocess.Popen(
        [executable],
        cwd="/home/user/app",
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    try:
        deadline = time.time() + 10
        while time.time() < deadline:
            assert process.poll() is None, "The secure-api process exited before serving requests."
            try:
                with socket.create_connection(("127.0.0.1", 8080), timeout=0.25):
                    break
            except OSError:
                time.sleep(0.1)
        else:
            raise AssertionError("The secure-api server did not start on port 8080.")

        assert _post_registration("a" * 11) == 400, \
            "The running registration handler accepted an 11-character password."
        assert _post_registration("a" * 12) == 200, \
            "The running registration handler rejected a 12-character password."
    finally:
        process.terminate()
        try:
            process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=3)


def test_database_schema_migrated():
    """Test that data.db contains the complete supplied users schema."""
    db_path = "/home/user/app/data.db"
    assert os.path.isfile(db_path), f"Database file {db_path} does not exist."

    conn = sqlite3.connect(db_path)
    try:
        cursor = conn.cursor()
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='users';")
        table = cursor.fetchone()
        assert table is not None, "The 'users' table does not exist in data.db."

        cursor.execute("PRAGMA table_info(users)")
        columns = cursor.fetchall()
        simplified = [(row[1], row[2].upper(), row[3], row[5]) for row in columns]
        assert simplified == [
            ("id", "INTEGER", 0, 1),
            ("username", "TEXT", 1, 0),
            ("password_hash", "TEXT", 1, 0),
        ], f"The users table columns do not match schema.sql: {simplified!r}"

        cursor.execute("SELECT sql FROM sqlite_master WHERE type='table' AND name='users'")
        create_sql = cursor.fetchone()[0]
        assert re.search(r'\bAUTOINCREMENT\b', create_sql, re.IGNORECASE), \
            "The users.id column is missing AUTOINCREMENT."

        cursor.execute("PRAGMA index_list(users)")
        unique_indexes = [row[1] for row in cursor.fetchall() if row[2] == 1]
        unique_column_sets = []
        for index_name in unique_indexes:
            cursor.execute(f'PRAGMA index_info("{index_name}")')
            unique_column_sets.append([row[2] for row in cursor.fetchall()])
        assert ["username"] in unique_column_sets, \
            "The users.username column does not have the required UNIQUE constraint."

        # Exercise the migrated constraints without retaining verifier rows.
        cursor.execute("SAVEPOINT verifier_schema_test")
        cursor.execute(
            "INSERT INTO users(username, password_hash) VALUES (?, ?)",
            ("__verifier_unique_user__", "hash"),
        )
        try:
            cursor.execute(
                "INSERT INTO users(username, password_hash) VALUES (?, ?)",
                ("__verifier_unique_user__", "other"),
            )
            raise AssertionError("Duplicate usernames are accepted by the users table.")
        except sqlite3.IntegrityError:
            pass
        cursor.execute("ROLLBACK TO verifier_schema_test")
        cursor.execute("RELEASE verifier_schema_test")
    finally:
        conn.close()


def test_nginx_configuration_valid():
    """Test that the Nginx configuration is valid."""
    nginx_conf_path = "/home/user/nginx.conf"
    assert os.path.isfile(nginx_conf_path), f"File {nginx_conf_path} does not exist."

    result = subprocess.run(
        ["nginx", "-t", "-c", nginx_conf_path],
        capture_output=True,
        text=True
    )
    assert result.returncode == 0, f"Nginx configuration test failed:\n{result.stderr}"


def _parse_nginx_directives(content):
    """Return (enclosing block headers, directive tokens) for active directives."""
    content = re.sub(r'#.*$', '', content, flags=re.MULTILINE)
    tokens = re.findall(r'[{};]|[^\s{};]+', content)
    stack = []
    pending = []
    directives = []
    for token in tokens:
        if token == '{':
            assert pending, "Nginx block has no header."
            stack.append(tuple(pending))
            pending = []
        elif token == ';':
            assert pending, "Empty Nginx directive."
            directives.append((tuple(stack), tuple(pending)))
            pending = []
        elif token == '}':
            assert not pending, "Unterminated Nginx directive before closing brace."
            assert stack, "Unexpected closing brace in Nginx configuration."
            stack.pop()
        else:
            pending.append(token)
    assert not pending and not stack, "Unbalanced or unterminated Nginx configuration."
    return directives


def test_nginx_rate_limiting_configured():
    """Test exact directives and ensure limit_req is in the /api/ location."""
    nginx_conf_path = "/home/user/nginx.conf"
    with open(nginx_conf_path, "r") as f:
        content = f.read()

    # Preserve the original textual assertions.
    assert re.search(r'limit_req_zone\s+\$binary_remote_addr\s+zone=api_limit:10m\s+rate=5r/s\s*;', content), \
        "Nginx config is missing the correct limit_req_zone directive."
    assert re.search(r'limit_req\s+zone=api_limit\s+burst=10\s+nodelay\s*;', content), \
        "Nginx config is missing the correct limit_req directive in the location block."

    directives = _parse_nginx_directives(content)
    expected_zone = (
        "limit_req_zone", "$binary_remote_addr", "zone=api_limit:10m", "rate=5r/s"
    )
    expected_limit = ("limit_req", "zone=api_limit", "burst=10", "nodelay")

    assert any(
        directive == expected_zone and any(block == ("http",) for block in blocks)
        for blocks, directive in directives
    ), "The active api_limit zone is not correctly declared in the http block."

    assert any(
        directive == expected_limit and any(
            len(block) >= 2 and block[0] == "location" and block[1] == "/api/"
            for block in blocks
        )
        for blocks, directive in directives
    ), "The active limit_req directive is not inside the /api/ location block."


def test_status_log_success():
    """Test that the status.log file contains SUCCESS."""
    status_log_path = "/home/user/status.log"
    assert os.path.isfile(status_log_path), f"File {status_log_path} does not exist."

    with open(status_log_path, "r") as f:
        content = f.read().strip()

    assert content == "SUCCESS", f"Expected 'SUCCESS' in status.log, but found '{content}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
