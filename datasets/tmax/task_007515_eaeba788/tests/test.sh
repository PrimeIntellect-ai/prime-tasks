#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import stat
import string
import subprocess

PROJECT_DIR = "/home/user/redactor"
INPUT_PATH = "/home/user/incident_logs/app_trace.log"
OUTPUT_PATH = "/home/user/incident_logs/app_trace_safe.log"


def test_rust_project_exists():
    """Check if the Rust project directory exists."""
    dir_path = PROJECT_DIR
    assert os.path.isdir(dir_path), f"Rust project directory {dir_path} does not exist."
    cargo_toml = os.path.join(dir_path, "Cargo.toml")
    assert os.path.isfile(cargo_toml), f"Cargo.toml not found in {dir_path}. Is it a valid Rust project?"


def test_rust_source_exists():
    """Check that the executable project contains Rust source code."""
    main_rs = os.path.join(PROJECT_DIR, "src", "main.rs")
    assert os.path.isfile(main_rs), f"Rust executable source {main_rs} does not exist."
    assert os.path.getsize(main_rs) > 0, f"Rust executable source {main_rs} is empty."


def test_safe_log_exists():
    """Check if the sanitized log file was created."""
    file_path = OUTPUT_PATH
    assert os.path.isfile(file_path), f"Sanitized log file {file_path} does not exist."


def test_safe_log_permissions():
    """Check if the sanitized log file has exactly 0400 permissions."""
    file_path = OUTPUT_PATH
    assert os.path.isfile(file_path), f"File {file_path} does not exist."

    file_stat = os.stat(file_path)
    permissions = stat.S_IMODE(file_stat.st_mode)
    assert permissions == 0o400, f"Expected permissions 0o400 (read-only for owner), but got {oct(permissions)}."


def test_safe_log_content():
    """Check if the sanitized log file has the correctly redacted content."""
    file_path = OUTPUT_PATH
    assert os.path.isfile(file_path), f"File {file_path} does not exist."

    expected_content = (
        "[INFO] User logged in. SESSION_TOKEN=[REDACTED]\n"
        "[DEBUG] Connecting to DB. PASSWORD=[REDACTED]\n"
        "[INFO] Action executed by SESSION_TOKEN=[REDACTED]\n"
        "[ERROR] Failed auth. PASSWORD=[REDACTED]\n"
        "[INFO] Normal log entry without sensitive data."
    )

    with open(file_path, "r") as f:
        actual_content = f.read().strip()

    assert actual_content == expected_content, "The content of the sanitized log does not match the expected redacted output."


def _cargo(command, timeout=180):
    result = subprocess.run(
        command,
        cwd=PROJECT_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=timeout,
    )
    assert result.returncode == 0, f"Command {' '.join(command)} failed:\n{result.stdout}"


def test_build_and_run_on_modified_input():
    """Rebuild and execute the Rust utility against unpredictable log contents."""
    with open(INPUT_PATH, "r", encoding="utf-8") as f:
        original_input = f.read()

    alphabet = string.ascii_letters + string.digits
    password_alphabet = alphabet + "!@#$%^&*_-+=:,.?"
    tokens = ["".join(secrets.choice(alphabet) for _ in range(16)) for _ in range(3)]
    passwords = ["".join(secrets.choice(password_alphabet) for _ in range(23)) for _ in range(2)]

    dynamic_input = (
        f"[TRACE] alpha SESSION_TOKEN={tokens[0]} marker PASSWORD={passwords[0]} tail\n"
        f"[TRACE] SESSION_TOKEN={tokens[1]} SESSION_TOKEN={tokens[2]}\n"
        f"[WARN] PASSWORD={passwords[1]}\tkept\n"
        "[INFO] ordinary randomized test line\n"
    )
    expected = re.sub(r"SESSION_TOKEN=[A-Za-z0-9]{16}", "SESSION_TOKEN=[REDACTED]", dynamic_input)
    expected = re.sub(r"PASSWORD=\S+", "PASSWORD=[REDACTED]", expected)

    try:
        with open(INPUT_PATH, "w", encoding="utf-8") as f:
            f.write(dynamic_input)
        if os.path.lexists(OUTPUT_PATH):
            os.unlink(OUTPUT_PATH)

        _cargo(["cargo", "clean"])
        _cargo(["cargo", "build", "--quiet"])
        _cargo(["cargo", "run", "--quiet"])

        assert os.path.isfile(OUTPUT_PATH), "Running the Rust utility did not create the sanitized log."
        with open(OUTPUT_PATH, "r", encoding="utf-8") as f:
            actual = f.read()
        assert actual.strip() == expected.strip(), "The utility failed to redact a modified input correctly."
        permissions = stat.S_IMODE(os.stat(OUTPUT_PATH).st_mode)
        assert permissions == 0o400, f"Expected generated file permissions 0o400, got {oct(permissions)}."
    finally:
        with open(INPUT_PATH, "w", encoding="utf-8") as f:
            f.write(original_input)
        if os.path.lexists(OUTPUT_PATH):
            os.unlink(OUTPUT_PATH)
        subprocess.run(
            ["cargo", "run", "--quiet"],
            cwd=PROJECT_DIR,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=180,
            check=False,
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
