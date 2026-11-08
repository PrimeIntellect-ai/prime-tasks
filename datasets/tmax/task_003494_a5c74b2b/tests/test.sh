#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import importlib.util
import json
import os
import secrets
import stat
import subprocess
import sys
import pytest


def load_parser():
    path = "/home/user/parser.py"
    assert os.path.isfile(path), f"Expected file {path} to exist."
    spec = importlib.util.spec_from_file_location("parser_under_test", path)
    parser = importlib.util.module_from_spec(spec)
    try:
        spec.loader.exec_module(parser)
    except Exception as e:
        pytest.fail(f"Failed to import parser.py: {e}")
    return parser


def test_leaked_username_file():
    path = "/home/user/leaked_username.txt"
    assert os.path.isfile(path), f"Expected file {path} to exist."
    with open(path, "r") as f:
        content = f.read().strip()
    assert content == "admin_no_semi_4920", f"Expected leaked username to be 'admin_no_semi_4920', got '{content}'"


def test_parser_behavior():
    parser = load_parser()
    assert hasattr(parser, "process_log"), "parser.py missing process_log function."
    assert callable(parser.process_log), "parser.process_log must be callable."

    # Preserve the original fixed checks.
    try:
        result = parser.process_log("USER_LOGIN: valid_user;")
        assert result is True, "process_log should return True for a valid log line."
    except Exception as e:
        pytest.fail(f"process_log raised an exception for a valid line: {e}")

    with pytest.raises(ValueError) as excinfo:
        parser.process_log("USER_LOGIN: admin_no_semi_4920")
    assert "Missing semicolon" in str(excinfo.value), "ValueError message should be 'Missing semicolon'."

    if hasattr(parser, "leaked_records"):
        assert "admin_no_semi_4920" not in parser.leaked_records, "The username was incorrectly appended to leaked_records."

    # Exercise general behavior on verifier-generated usernames unknown to the submission.
    before = None
    if hasattr(parser, "leaked_records") and isinstance(parser.leaked_records, list):
        before = list(parser.leaked_records)

    generated = ["audit_" + secrets.token_hex(12) for _ in range(32)]
    for username in generated:
        assert parser.process_log(f"USER_LOGIN: {username};") is True, \
            f"process_log should return True for valid username {username!r}."

        with pytest.raises(ValueError) as excinfo:
            parser.process_log(f"USER_LOGIN: {username}")
        assert str(excinfo.value) == "Missing semicolon", \
            "Unterminated USER_LOGIN lines must raise ValueError('Missing semicolon')."

    if before is not None:
        assert parser.leaked_records == before, \
            "Malformed records must not be appended to leaked_records."


def clear_parser_bytecode():
    for path in glob.glob("/home/user/__pycache__/parser*.pyc"):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass


def run_regression_script(path):
    return subprocess.run(
        [sys.executable, path],
        capture_output=True,
        text=True,
        cwd="/home/user",
        timeout=20,
    )


def test_test_parser_script():
    path = "/home/user/test_parser.py"
    parser_path = "/home/user/parser.py"
    assert os.path.isfile(path), f"Expected file {path} to exist."

    with open(path, "r") as f:
        content = f.read()
    assert "admin_no_semi_4920" in content, "test_parser.py must test the specific leaked username discovered."

    # Preserve the original execution check against the submitted parser.
    result = run_regression_script(path)
    assert result.returncode == 0, f"test_parser.py failed to run. Output:\n{result.stdout}\n{result.stderr}"

    # Mutation-check the regression test: it must call process_log with the
    # malformed leaked username and fail when that call no longer raises.
    with open(parser_path, "rb") as f:
        original_parser = f.read()
    original_mode = stat.S_IMODE(os.stat(parser_path).st_mode)
    record_path = "/tmp/test_parser_calls_" + secrets.token_hex(10) + ".jsonl"

    def install_spy(raise_missing):
        source = f'''import json\nleaked_records = []\n_RECORD = {record_path!r}\n_RAISE = {raise_missing!r}\n\ndef process_log(log_line):\n    with open(_RECORD, "a", encoding="utf-8") as out:\n        out.write(json.dumps(log_line) + "\\n")\n    if _RAISE and "USER_LOGIN:" in log_line and ";" not in log_line:\n        raise ValueError("Missing semicolon")\n    return ";" in log_line\n'''
        with open(parser_path, "w", encoding="utf-8") as f:
            f.write(source)
        clear_parser_bytecode()

    try:
        install_spy(True)
        passing = run_regression_script(path)
        assert passing.returncode == 0, \
            f"test_parser.py did not pass when process_log correctly raised ValueError. Output:\n{passing.stdout}\n{passing.stderr}"

        assert os.path.isfile(record_path), "test_parser.py did not call process_log from parser.py."
        with open(record_path, "r", encoding="utf-8") as f:
            calls = [json.loads(line) for line in f if line.strip()]
        assert any(
            isinstance(line, str)
            and "USER_LOGIN:" in line
            and "admin_no_semi_4920" in line
            and ";" not in line
            for line in calls
        ), "test_parser.py must pass the malformed leaked username to process_log."

        os.remove(record_path)
        install_spy(False)
        failing = run_regression_script(path)
        assert failing.returncode != 0, \
            "test_parser.py must fail when process_log does not raise ValueError for the malformed line."

        assert os.path.isfile(record_path), "test_parser.py did not call process_log during the mutation check."
    finally:
        with open(parser_path, "wb") as f:
            f.write(original_parser)
        os.chmod(parser_path, original_mode)
        clear_parser_bytecode()
        try:
            os.remove(record_path)
        except FileNotFoundError:
            pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
