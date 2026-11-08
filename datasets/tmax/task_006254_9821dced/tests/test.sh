#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import subprocess
import sys

import pytest

INPUT_PATH = "/home/user/incoming_logs.txt"
OUTPUT_PATH = "/home/user/extracted_users.txt"
PARSER_PATH = "/home/user/parser.py"


def run_parser():
    return subprocess.run(
        [sys.executable, PARSER_PATH],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )


@pytest.fixture(scope="session", autouse=True)
def execute_and_exercise_parser():
    assert os.path.isfile(PARSER_PATH), f"Expected parser {PARSER_PATH} does not exist."

    with open(INPUT_PATH, "rb") as f:
        original_input = f.read()

    generated_ids = [f"T-{secrets.token_hex(8)}" for _ in range(3)]
    hidden_lines = [
        json.dumps({"event": {"user": {"id": generated_ids[0], "role": "test"}}}),
        '{"event": {"user": ',
        json.dumps({"event": {"user": {"name": "missing-id"}}}),
        json.dumps({"event": {"user": {"id": generated_ids[1]}}}),
        json.dumps({"other": {"user": {"id": "wrong-path"}}}),
        json.dumps({"event": {"metadata": "missing-user"}}),
        json.dumps({"event": {"user": {"id": generated_ids[2], "extra": True}}}),
    ]

    hidden_proc = None
    hidden_output = None
    hidden_exception = None
    try:
        with open(INPUT_PATH, "w") as f:
            f.write("\n".join(hidden_lines) + "\n")
        if os.path.exists(OUTPUT_PATH):
            os.remove(OUTPUT_PATH)

        hidden_proc = run_parser()
        if os.path.isfile(OUTPUT_PATH):
            with open(OUTPUT_PATH, "r") as f:
                hidden_output = f.read().splitlines()
    except Exception as exc:
        hidden_exception = exc
    finally:
        with open(INPUT_PATH, "wb") as f:
            f.write(original_input)
        if os.path.exists(OUTPUT_PATH):
            os.remove(OUTPUT_PATH)

    final_proc = run_parser()

    assert hidden_exception is None, f"Parser failed while processing generated edge cases: {hidden_exception}"
    assert hidden_proc.returncode == 0, f"Parser crashed on generated edge cases:\n{hidden_proc.stderr}"
    assert hidden_output == generated_ids, (
        f"Parser produced {hidden_output!r} for generated input; expected {generated_ids!r}."
    )
    assert final_proc.returncode == 0, f"Parser crashed on incoming_logs.txt:\n{final_proc.stderr}"

    yield


def test_extracted_users_exists_and_correct():
    output_path = "/home/user/extracted_users.txt"
    assert os.path.isfile(output_path), f"Expected output file {output_path} does not exist. Did you run the script?"

    with open(output_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_users = ["U1001", "U1002", "U1003", "U1004"]
    assert lines == expected_users, f"Expected extracted users to be {expected_users}, but got {lines}."


def test_incoming_logs_unmodified():
    input_path = "/home/user/incoming_logs.txt"
    assert os.path.isfile(input_path), f"Input file {input_path} is missing."

    with open(input_path, "r") as f:
        lines = f.read().splitlines()

    expected_lines = [
        '{"event": {"user": {"id": "U1001", "role": "admin"}}}',
        '{"event": {"user": {"id": "U1002", "role": "user"}}}',
        '{"event": {"user": {"name": "Alice_No_ID"}}}',
        '{"event": {"user": {"id": "U1003", "role": "user"}}}',
        '{"event": "corrupted_payload_missing_braces"',
        '{"event": {"user": {"id": "U1004", "role": "guest"}}}'
    ]
    assert lines == expected_lines, "The incoming_logs.txt file was modified. You were instructed not to change the input file."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
