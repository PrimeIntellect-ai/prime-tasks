#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import pwd
import secrets
import subprocess
import sys
from pathlib import Path

import pytest

SCRIPT_PATH = Path("/home/user/process_logs.py")
INPUT_PATH = Path("/home/user/app_dirty.log")
OUTPUT_PATH = Path("/home/user/clean_inserts.sql")

EXPECTED_ORIGINAL = [
    "INSERT INTO user_activity (event_time, ip_address, user_email) VALUES ('2023-10-12 08:23:45', '192.168.1.100', 'alice@example.com');",
    "INSERT INTO user_activity (event_time, ip_address, user_email) VALUES ('2023-10-12 08:25:01', '172.16.254.1', 'bob.smith@domain.co.uk');",
    "INSERT INTO user_activity (event_time, ip_address, user_email) VALUES ('2023-10-12 08:30:00', '8.8.8.8', 'charlie@company.com');",
    "INSERT INTO user_activity (event_time, ip_address, user_email) VALUES ('2023-10-12 09:05:22', '127.0.0.1', 'admin@localhost');",
]


def output_lines():
    with OUTPUT_PATH.open("r", encoding="utf-8") as f:
        return [line.strip() for line in f if line.strip()]


def run_script():
    user = pwd.getpwnam("user")

    def demote():
        os.setgroups([])
        os.setgid(user.pw_gid)
        os.setuid(user.pw_uid)

    return subprocess.run(
        [sys.executable, str(SCRIPT_PATH)],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
        preexec_fn=demote,
    )


def write_input(text):
    if INPUT_PATH.exists() or INPUT_PATH.is_symlink():
        INPUT_PATH.unlink()
    INPUT_PATH.write_text(text, encoding="utf-8")
    INPUT_PATH.chmod(0o644)


def test_script_exists():
    script_path = "/home/user/process_logs.py"
    assert os.path.exists(script_path), f"The script {script_path} does not exist."
    assert os.path.isfile(script_path), f"{script_path} is not a file."


def test_script_uses_streaming():
    script_path = "/home/user/process_logs.py"
    with open(script_path, 'r', encoding='utf-8') as f:
        content = f.read()

    # Check that it doesn't use .read() or .readlines()
    assert ".read()" not in content, "The script should not load the entire file into memory using .read()."
    assert ".readlines()" not in content, "The script should not load the entire file into memory using .readlines()."

    tree = ast.parse(content, filename=script_path)
    forbidden = [
        node for node in ast.walk(tree)
        if isinstance(node, ast.Call)
        and isinstance(node.func, ast.Attribute)
        and node.func.attr in {"read", "readlines"}
    ]
    assert not forbidden, "The script must process the input line-by-line rather than calling read/readlines."


def test_output_file_exists():
    output_path = "/home/user/clean_inserts.sql"
    assert os.path.exists(output_path), f"The output file {output_path} does not exist."
    assert os.path.isfile(output_path), f"{output_path} is not a file."


def test_output_file_contents():
    actual_lines = output_lines()
    assert len(actual_lines) == len(EXPECTED_ORIGINAL), f"Expected {len(EXPECTED_ORIGINAL)} statements, found {len(actual_lines)}."

    for i, (actual, expected) in enumerate(zip(actual_lines, EXPECTED_ORIGINAL)):
        assert actual == expected, f"Mismatch on line {i + 1}.\nExpected: {expected}\nActual: {actual}"


def test_script_uses_regex_and_template_formatting():
    content = SCRIPT_PATH.read_text(encoding="utf-8")
    tree = ast.parse(content, filename=str(SCRIPT_PATH))

    regex_methods = {"compile", "search", "match", "fullmatch", "findall", "finditer"}
    regex_calls = [
        node for node in ast.walk(tree)
        if isinstance(node, ast.Call)
        and (
            (isinstance(node.func, ast.Attribute) and node.func.attr in regex_methods)
            or (isinstance(node.func, ast.Name) and node.func.id in regex_methods)
        )
    ]
    assert regex_calls, "The script must use regular expressions to extract the fields."

    uses_template = any(isinstance(node, ast.JoinedStr) for node in ast.walk(tree))
    uses_template = uses_template or any(
        isinstance(node, ast.Call)
        and (
            (isinstance(node.func, ast.Attribute) and node.func.attr in {"format", "format_map", "substitute", "safe_substitute"})
            or (isinstance(node.func, ast.Name) and node.func.id == "Template")
        )
        for node in ast.walk(tree)
    )
    uses_template = uses_template or any(
        isinstance(node, ast.BinOp) and isinstance(node.op, ast.Mod)
        for node in ast.walk(tree)
    )
    assert uses_template, "The SQL statements must be generated using string formatting or templating."


def test_executing_script_generates_original_output():
    if OUTPUT_PATH.exists() or OUTPUT_PATH.is_symlink():
        OUTPUT_PATH.unlink()

    result = run_script()
    assert result.returncode == 0, f"process_logs.py failed:\n{result.stderr}"
    assert OUTPUT_PATH.is_file(), "Executing process_logs.py did not create clean_inserts.sql."
    assert output_lines() == EXPECTED_ORIGINAL, "Executing the script did not reproduce the required original output."


def test_script_processes_unseen_log_data():
    original_input = INPUT_PATH.read_text(encoding="utf-8")
    token = secrets.token_hex(6)
    octet = secrets.randbelow(200) + 20

    cases = [
        ("2041-02-03 04:05:06", f"198.51.100.{octet}", f"first.{token}@example.net"),
        ("2042-11-12 13:14:15", "203.0.113.77", f"second+{token}@sub.example.org"),
        ("2043-06-07 18:19:20", "192.0.2.44", f"third_{token}@example.com"),
    ]

    dynamic_log = "\n".join([
        f"NOTICE user={cases[0][2]} connected at {cases[0][0]} through IP {cases[0][1]}.",
        "DEBUG 10.20.30.40 has no timestamp or email and must be skipped.",
        f"WARN source {cases[1][1]}; account {cases[1][2]}; time {cases[1][0]}!",
        f"ERROR {cases[2][0]} request by {cases[2][2]} originated from {cases[2][1]}.",
        "INFO 2044-01-01 00:00:00 and nobody@example.com are missing an IP.",
        "INFO 192.0.2.99 and somebody@example.com are missing a timestamp.",
    ]) + "\n"

    expected = [
        f"INSERT INTO user_activity (event_time, ip_address, user_email) VALUES ('{timestamp}', '{ip}', '{email}');"
        for timestamp, ip, email in cases
    ]

    try:
        write_input(dynamic_log)
        if OUTPUT_PATH.exists() or OUTPUT_PATH.is_symlink():
            OUTPUT_PATH.unlink()

        result = run_script()
        assert result.returncode == 0, f"process_logs.py failed on unseen input:\n{result.stderr}"
        assert OUTPUT_PATH.is_file(), "The script did not create clean_inserts.sql on unseen input."
        assert output_lines() == expected, "The script did not correctly extract and format unseen log records."
    finally:
        write_input(original_input)
        if OUTPUT_PATH.exists() or OUTPUT_PATH.is_symlink():
            OUTPUT_PATH.unlink()
        restore = run_script()
        assert restore.returncode == 0, f"process_logs.py failed while restoring original output:\n{restore.stderr}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
