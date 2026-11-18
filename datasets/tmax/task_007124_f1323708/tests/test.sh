#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import secrets
import stat
import subprocess
import difflib
import pytest

PARSER_PATH = "/home/user/parser.py"
SERVER_PATH = "/home/user/server.log"


def test_parser_artifact_executes_on_original_log():
    assert os.path.exists(PARSER_PATH), f"Missing required file: {PARSER_PATH}"
    assert stat.S_ISREG(os.stat(PARSER_PATH).st_mode), f"{PARSER_PATH} is not a regular file"

    result = subprocess.run(
        ["python3", PARSER_PATH],
        cwd="/home/user",
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"Executing {PARSER_PATH} failed.\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
    )


def test_valid_users_content():
    valid_users_path = "/home/user/valid_users.txt"
    assert os.path.exists(valid_users_path), f"Missing required file: {valid_users_path}"

    with open(valid_users_path, "r") as f:
        users = [line.strip() for line in f if line.strip()]

    expected_users = ["u1", "u4", "u5"]
    assert users == expected_users, f"Content of {valid_users_path} is incorrect. Expected {expected_users}, got {users}"


def test_all_users_content():
    all_users_path = "/home/user/all_users.txt"
    assert os.path.exists(all_users_path), f"Missing required file: {all_users_path}"

    with open(all_users_path, "r") as f:
        users = [line.strip() for line in f if line.strip()]

    expected_users = ["u0", "u1", "u4", "u5", "u8"]
    assert users == expected_users, f"Content of {all_users_path} is incorrect. Expected {expected_users}, got {users}"


def test_update_patch_content():
    patch_path = "/home/user/update.patch"
    historical_path = "/home/user/historical.txt"
    all_users_path = "/home/user/all_users.txt"

    assert os.path.exists(patch_path), f"Missing required file: {patch_path}"
    assert os.path.exists(historical_path), f"Missing required file: {historical_path}"
    assert os.path.exists(all_users_path), f"Missing required file: {all_users_path}"

    with open(historical_path, "r") as f:
        hist_lines = f.readlines()
    with open(all_users_path, "r") as f:
        all_lines = f.readlines()

    expected_diff = list(difflib.unified_diff(
        hist_lines, all_lines,
        fromfile=historical_path,
        tofile=all_users_path
    ))

    with open(patch_path, "r") as f:
        actual_diff = f.readlines()

    assert len(actual_diff) >= 3, "update.patch does not appear to be a valid unified diff."
    assert actual_diff[2:] == expected_diff[2:], "The hunks in update.patch do not match the expected unified diff between historical.txt and all_users.txt."


def test_pytest_execution():
    test_file_path = "/home/user/test_parser.py"
    assert os.path.exists(test_file_path), f"Missing required file: {test_file_path}"

    result = subprocess.run(
        ["pytest", test_file_path],
        capture_output=True,
        text=True
    )

    assert result.returncode == 0, f"pytest failed on {test_file_path}.\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"


def test_unit_test_file_imports_parser_and_contains_tests():
    test_file_path = "/home/user/test_parser.py"
    with open(test_file_path, "r") as f:
        tree = ast.parse(f.read(), filename=test_file_path)

    imports_parser = any(
        (isinstance(node, ast.Import) and any(alias.name == "parser" for alias in node.names))
        or (isinstance(node, ast.ImportFrom) and node.module == "parser")
        for node in ast.walk(tree)
    )
    test_functions = [
        node for node in ast.walk(tree)
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))
        and node.name.startswith("test_")
    ]

    assert imports_parser, "test_parser.py must import logic from parser.py"
    assert len(test_functions) >= 2, "test_parser.py must contain tests for both valid and invalid sequences"


def _is_valid(events):
    allowed = {
        "OFFLINE": {"CONNECT": "CONNECT"},
        "CONNECT": {"AUTH": "AUTH", "DISCONNECT": "DISCONNECT"},
        "AUTH": {"REQUEST": "REQUEST", "DISCONNECT": "DISCONNECT"},
        "REQUEST": {"REQUEST": "REQUEST", "DISCONNECT": "DISCONNECT"},
        "DISCONNECT": {},
    }
    state = "OFFLINE"
    valid = True
    for event in events:
        if event not in allowed[state]:
            valid = False
        elif valid:
            state = allowed[state][event]
    return valid and state == "DISCONNECT"


def test_parser_state_machine_on_unseen_log():
    tracked_paths = [
        SERVER_PATH,
        "/home/user/historical.txt",
        "/home/user/valid_users.txt",
        "/home/user/all_users.txt",
        "/home/user/update.patch",
    ]
    saved = {}
    for path in tracked_paths:
        if os.path.exists(path):
            with open(path, "rb") as f:
                saved[path] = f.read()
        else:
            saved[path] = None

    token = secrets.token_hex(8)
    sequences = {
        f"full_{token}": ["CONNECT", "AUTH", "REQUEST", "REQUEST", "DISCONNECT"],
        f"short_{token}": ["CONNECT", "DISCONNECT"],
        f"authdisc_{token}": ["CONNECT", "AUTH", "DISCONNECT"],
        f"offline_request_{token}": ["REQUEST", "CONNECT", "DISCONNECT"],
        f"double_connect_{token}": ["CONNECT", "CONNECT", "DISCONNECT"],
        f"unfinished_{token}": ["CONNECT", "AUTH", "REQUEST"],
        f"bad_after_auth_{token}": ["CONNECT", "AUTH", "AUTH", "DISCONNECT"],
    }

    events = ["CONNECT", "AUTH", "REQUEST", "DISCONNECT"]
    for index in range(16):
        user = f"random_{index}_{token}"
        sequences[user] = [secrets.choice(events) for _ in range(secrets.randbelow(7) + 1)]

    expected = sorted(user for user, seq in sequences.items() if _is_valid(seq))

    pending = {user: list(seq) for user, seq in sequences.items()}
    lines = []
    timestamp = 1
    while pending:
        user = secrets.choice(list(pending))
        event = pending[user].pop(0)
        lines.append(f"{timestamp} {user} {event}\n")
        timestamp += 1
        if not pending[user]:
            del pending[user]

    try:
        with open(SERVER_PATH, "w") as f:
            f.writelines(lines)
        if os.path.exists("/home/user/valid_users.txt"):
            os.remove("/home/user/valid_users.txt")

        result = subprocess.run(
            ["python3", PARSER_PATH],
            cwd="/home/user",
            capture_output=True,
            text=True,
            timeout=20,
        )
        assert result.returncode == 0, (
            f"Parser failed on an unseen log.\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
        )
        assert os.path.isfile("/home/user/valid_users.txt"), "Parser did not create valid_users.txt"

        with open("/home/user/valid_users.txt", "r") as f:
            actual = [line.strip() for line in f if line.strip()]
        assert actual == expected, f"Parser produced {actual}; expected {expected} for the unseen log"
    finally:
        for path, content in saved.items():
            if content is None:
                if os.path.exists(path):
                    os.remove(path)
            else:
                with open(path, "wb") as f:
                    f.write(content)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
