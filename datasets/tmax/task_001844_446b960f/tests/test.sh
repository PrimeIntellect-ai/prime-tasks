#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import sqlite3
import subprocess
import tempfile
import uuid


def test_security_test_log_exists_and_correct():
    log_path = "/home/user/security_test.log"
    assert os.path.isfile(log_path), f"{log_path} is missing. Did you redirect the output of test_auth.sh?"

    with open(log_path, "r") as f:
        content = f.read()

    assert "LOGIN_SUCCESS" in content, "Log file missing LOGIN_SUCCESS for valid login. The valid login attempt failed."
    assert "LOGIN_FAILED" in content, "Log file missing LOGIN_FAILED for SQL injection attempt. The injection attempt succeeded or wasn't handled properly."

    lines = [line.strip() for line in content.splitlines() if line.strip()]
    assert lines == [
        "Testing valid login...",
        "LOGIN_SUCCESS",
        "Testing SQL Injection...",
        "LOGIN_FAILED",
    ], "security_test.log does not contain the expected integration-test results"


def test_db_schema_updated():
    db_path = "/home/user/auth_service/db.sqlite"
    assert os.path.isfile(db_path), f"{db_path} is missing"

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    cursor.execute("PRAGMA table_info(users);")
    columns = cursor.fetchall()
    conn.close()

    role_col = None
    for col in columns:
        if col[1] == "role":
            role_col = col
            break

    assert role_col is not None, "Column 'role' missing in users table. The schema migration was not applied."
    assert role_col[2].upper() == "TEXT", f"Column 'role' must be of type TEXT, but got {role_col[2]}"
    assert role_col[4] == "'user'", f"Column 'role' default value should be 'user', got {role_col[4]}"


def test_auth_api_fixed_with_parameterized_queries():
    cpp_path = "/home/user/auth_service/auth_api.cpp"
    assert os.path.isfile(cpp_path), f"{cpp_path} is missing"

    with open(cpp_path, "r") as f:
        content = f.read()

    assert "sqlite3_bind_text" in content, "auth_api.cpp does not contain sqlite3_bind_text. Parameterized queries were not implemented."


def test_binary_built():
    bin_path = "/home/user/auth_service/auth_api"
    assert os.path.isfile(bin_path), f"{bin_path} is missing. Did you run make?"
    assert os.access(bin_path, os.X_OK), f"{bin_path} is not executable."
    with open(bin_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "auth_api is not a compiled native executable"


def create_database(path, users):
    conn = sqlite3.connect(path)
    conn.execute("CREATE TABLE users (id INTEGER PRIMARY KEY, username TEXT, password TEXT, role TEXT DEFAULT 'user')")
    conn.executemany("INSERT INTO users (username, password) VALUES (?, ?)", users)
    conn.commit()
    conn.close()


def exercise_binary(binary, users, cases):
    for username, password, expected in cases:
        with tempfile.TemporaryDirectory() as workdir:
            create_database(os.path.join(workdir, "db.sqlite"), users)
            result = subprocess.run(
                [binary, username, password],
                cwd=workdir,
                text=True,
                capture_output=True,
                timeout=10,
            )
            assert result.returncode == 0, (
                f"auth_api exited with {result.returncode} for a login attempt; "
                f"stderr: {result.stderr!r}"
            )
            assert result.stdout.strip() == expected, (
                f"Expected {expected} for username {username!r}, but got "
                f"stdout={result.stdout!r}, stderr={result.stderr!r}"
            )


def test_built_api_and_source_resist_sql_injection():
    token = uuid.uuid4().hex
    username = "account_" + token
    password = "secret_" + uuid.uuid4().hex
    quoted_username = "o'reilly_" + uuid.uuid4().hex
    quoted_password = "p'ass_" + uuid.uuid4().hex
    users = [(username, password), (quoted_username, quoted_password)]

    cases = [
        (username, password, "LOGIN_SUCCESS"),
        (quoted_username, quoted_password, "LOGIN_SUCCESS"),
        (username, password + "_wrong", "LOGIN_FAILED"),
        (username + "' --", "anything", "LOGIN_FAILED"),
        ("' OR 1=1 --", "anything", "LOGIN_FAILED"),
        ("missing_" + token, "' OR 1=1 --", "LOGIN_FAILED"),
        (username, "x' OR '1'='1", "LOGIN_FAILED"),
    ]

    built_binary = "/home/user/auth_service/auth_api"
    exercise_binary(built_binary, users, cases)

    with tempfile.TemporaryDirectory() as builddir:
        rebuilt_binary = os.path.join(builddir, "auth_api_rebuilt")
        compile_result = subprocess.run(
            [
                "g++", "-Wall", "-Wextra", "-std=c++17",
                "/home/user/auth_service/auth_api.cpp",
                "-o", rebuilt_binary, "-lsqlite3",
            ],
            text=True,
            capture_output=True,
            timeout=30,
        )
        assert compile_result.returncode == 0, (
            "auth_api.cpp does not compile: " + compile_result.stderr
        )
        exercise_binary(rebuilt_binary, users, cases)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
