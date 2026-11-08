#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import re
import secrets
import string
import subprocess
import tempfile
import pytest


def run_app(bin_path, username, password):
    env = os.environ.copy()
    env["DB_PASSWORD"] = password
    return subprocess.run(
        [bin_path, f"--username={username}"],
        env=env,
        capture_output=True,
        text=True,
        timeout=10,
    )


def assert_app_behavior(bin_path):
    # Preserve the original fixed credential assertion.
    password = "N3wR0D4tionPass!2024"
    expected_hash = hashlib.sha256(password.encode()).hexdigest()
    env = os.environ.copy()
    env["DB_PASSWORD"] = password
    result = subprocess.run(
        [bin_path, "--username=admin"], env=env, capture_output=True, text=True, timeout=10
    )
    assert result.returncode == 0
    assert expected_hash in result.stdout, "App did not output the expected hash using DB_PASSWORD."

    # Exercise independently generated usernames and passwords.
    for _ in range(6):
        username = "user_" + secrets.token_hex(8)
        password = secrets.token_urlsafe(24) + secrets.token_hex(5)
        expected = hashlib.sha256(password.encode()).hexdigest()
        result = run_app(bin_path, username, password)
        assert result.returncode == 0, result.stderr + result.stdout
        assert result.stdout == f"Connecting user {username} with password hash {expected}\n"

    # The old flag must be absent even when DB_PASSWORD is set.
    result_fail = subprocess.run(
        [bin_path, "--password=secret"], env=env, capture_output=True, text=True, timeout=10
    )
    assert result_fail.returncode != 0, "App should fail when --password is provided."
    output = result_fail.stderr + result_fail.stdout
    assert "provided but not defined" in output or "flag provided but not defined: -password" in output, \
        "App did not fail with the expected flag parsing error for --password."

    # No other environment variable may substitute for DB_PASSWORD.
    missing_env = os.environ.copy()
    missing_env.pop("DB_PASSWORD", None)
    missing_env["PASSWORD"] = secrets.token_urlsafe(20)
    missing_env["DATABASE_PASSWORD"] = secrets.token_urlsafe(20)
    missing = subprocess.run(
        [bin_path, "--username=nobody"],
        env=missing_env,
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert missing.returncode != 0
    assert "password required" in (missing.stdout + missing.stderr).lower()


def test_app_secure_binary_and_source():
    bin_path = "/home/user/app_secure"
    source_path = "/home/user/app.go"
    assert os.path.isfile(bin_path), f"Binary not found: {bin_path}"
    assert os.access(bin_path, os.X_OK), f"Binary is not executable: {bin_path}"
    assert os.path.isfile(source_path), f"Source not found: {source_path}"

    # Require an actual compiled Go executable rather than a script or output stub.
    with open(bin_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "app_secure is not an ELF executable"
    go_info = subprocess.run(
        ["go", "version", "-m", bin_path], capture_output=True, text=True, timeout=10
    )
    assert go_info.returncode == 0 and "go1" in go_info.stdout, \
        "app_secure does not contain Go build information"

    assert_app_behavior(bin_path)

    # Compile the submitted app.go independently and verify that the remediated
    # source itself implements the same required behavior.
    with tempfile.TemporaryDirectory() as tmp:
        rebuilt = os.path.join(tmp, "app_from_source")
        build = subprocess.run(
            ["go", "build", "-o", rebuilt, source_path],
            cwd="/home/user",
            capture_output=True,
            text=True,
            timeout=60,
        )
        assert build.returncode == 0, "Submitted app.go does not compile: " + build.stderr
        assert_app_behavior(rebuilt)


def test_id_rule():
    rule_path = "/home/user/id_rule.txt"
    assert os.path.isfile(rule_path), f"File not found: {rule_path}"

    with open(rule_path, "r") as f:
        raw = f.read()
    regex_str = raw.strip()
    assert regex_str, "Regex file is empty."
    assert len(raw.splitlines()) == 1, "id_rule.txt must contain only the raw regex."

    try:
        pattern = re.compile(regex_str)
    except re.error as e:
        pytest.fail(f"Invalid regex compiled: {e}")

    # Preserve the original examples.
    assert pattern.search("./app --password=secret123")
    assert not pattern.search("./app --password=")
    assert not pattern.search("./app --password= ")

    # Compare against the required semantics on unpredictable values and a
    # varied corpus so a literal fixed-string rule cannot pass.
    alphabet = string.ascii_letters + string.digits + "!@#$%^&*()_+-=[]{}:,.?/"
    corpus = [
        "./app",
        "--password",
        "password=value",
        "./app --username=--password=",
        "./app --password=\tvalue",
        "./app --password=\nvalue",
        "prefix--password= suffix",
        "unrelated non-whitespace text",
    ]
    for _ in range(30):
        token = "".join(secrets.choice(alphabet) for _ in range(secrets.randbelow(30) + 1))
        prefix = secrets.choice(["./app ", "sudo app ", "prefix", "x --flag=y "])
        suffix = secrets.choice(["", " --username=test", "\t--other=x", " trailing"])
        corpus.append(prefix + "--password=" + token + suffix)
        corpus.append(prefix + "--password=" + secrets.choice(["", " ", "\t"]))

    reference = re.compile(r"--password=\S+")
    for sample in corpus:
        assert bool(pattern.search(sample)) == bool(reference.search(sample)), \
            f"Regex has incorrect behavior for input: {sample!r}"


def test_rotation_summary():
    summary_path = "/home/user/rotation_summary.txt"
    assert os.path.isfile(summary_path), f"File not found: {summary_path}"

    with open(summary_path, "r") as f:
        lines = f.read().splitlines()

    # Preserve the original checks, then enforce the requested exact format.
    assert len(lines) >= 2, "Summary file must have at least two lines."
    cwe = lines[0]
    assert "CWE-214" in cwe or "CWE-314" in cwe, \
        f"Line 1 does not contain the correct CWE. Found: {cwe}"
    password = lines[1]
    assert password == "N3wR0D4tionPass!2024", \
        f"Line 2 does not contain the correct decoded password. Found: {password}"

    assert len(lines) == 2, "Summary file must contain exactly two lines."
    assert lines[0] in {"CWE-214", "CWE-314"}, "Line 1 must contain only the exact CWE ID."
    assert lines[1] == "N3wR0D4tionPass!2024"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
