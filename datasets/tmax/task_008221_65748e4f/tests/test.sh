#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import secrets
import subprocess
import sys
import tempfile
import pytest

PARSER = "/home/user/ticket_8412/parser.py"
INPUT_FILE = "/home/user/ticket_8412/container_logs.txt"
OUTPUT_FILE = "/home/user/ticket_8412/parsed_logs.jsonl"


@pytest.fixture(scope="session", autouse=True)
def execute_parser_on_required_files():
    assert os.path.exists(PARSER), f"The parser {PARSER} does not exist."
    assert os.path.isfile(PARSER), f"{PARSER} is not a regular file."
    assert os.path.isfile(INPUT_FILE), f"The input log file {INPUT_FILE} does not exist."

    try:
        result = subprocess.run(
            [sys.executable, PARSER, INPUT_FILE, OUTPUT_FILE],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("parser.py timed out when run on container_logs.txt")

    assert result.returncode == 0, (
        "parser.py failed when run with the required input and output paths.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def test_parser_handles_unseen_messages_with_square_brackets():
    token = secrets.token_hex(12)
    expected = [
        {
            "time": "2041-07-08 09:10:11",
            "level": "INFO",
            "message": f"ordinary message {token}",
        },
        {
            "time": "2041-07-08 09:10:12",
            "level": "WARN",
            "message": f"[Auth-{token}] Failed login for user [admin-{token}]",
        },
        {
            "time": "2041-07-08 09:10:13",
            "level": "DEBUG",
            "message": f"[left-{token}] [right-{token}] brackets remain intact",
        },
    ]

    raw_lines = [
        f"[{entry['time']}] [{entry['level']}] {entry['message']}"
        for entry in expected
    ]

    with tempfile.TemporaryDirectory() as tmpdir:
        test_input = os.path.join(tmpdir, "input.log")
        test_output = os.path.join(tmpdir, "output.jsonl")
        with open(test_input, "w", encoding="utf-8") as f:
            f.write("\n".join(raw_lines) + "\n")

        try:
            result = subprocess.run(
                [sys.executable, PARSER, test_input, test_output],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=10,
            )
        except subprocess.TimeoutExpired:
            pytest.fail("parser.py timed out on bracket-containing log messages")

        assert result.returncode == 0, (
            "parser.py crashed on unseen bracket-containing messages.\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
        assert os.path.isfile(test_output), "parser.py did not create its requested output file."

        parsed = []
        with open(test_output, "r", encoding="utf-8") as f:
            for line_num, line in enumerate(f, 1):
                if not line.strip():
                    continue
                try:
                    parsed.append(json.loads(line))
                except json.JSONDecodeError as exc:
                    pytest.fail(f"Generated line {line_num} is not valid JSON: {exc}")

        assert parsed == expected, (
            "parser.py did not correctly preserve bracket-containing messages.\n"
            f"Expected: {expected}\nActual: {parsed}"
        )


def test_parsed_logs_exist_and_correct():
    output_file = "/home/user/ticket_8412/parsed_logs.jsonl"

    assert os.path.exists(output_file), f"The output file {output_file} does not exist. Did you run the script?"
    assert os.path.isfile(output_file), f"{output_file} is not a file."

    parsed_lines = []
    with open(output_file, 'r') as f:
        for line_num, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            try:
                parsed_data = json.loads(line)
                parsed_lines.append(parsed_data)
            except json.JSONDecodeError:
                pytest.fail(f"Line {line_num} in {output_file} is not valid JSON: {line}")

    assert len(parsed_lines) == 5, f"Expected 5 parsed log entries, found {len(parsed_lines)}."

    # Verify the edge-case line
    edge_case_found = False
    for entry in parsed_lines:
        assert "time" in entry, "Missing 'time' key in JSON object."
        assert "level" in entry, "Missing 'level' key in JSON object."
        assert "message" in entry, "Missing 'message' key in JSON object."

        if entry["time"] == "2023-10-12 10:05:00":
            edge_case_found = True
            assert entry["level"] == "WARN", f"Expected level 'WARN', got {entry['level']}"
            expected_msg = "[AuthService] Failed login attempt for user [admin]"
            assert entry["message"] == expected_msg, f"Expected message '{expected_msg}', got '{entry['message']}'"

    assert edge_case_found, "The edge-case log entry for 10:05:00 was not found in the output file."


def test_all_logs_parsed_correctly():
    output_file = "/home/user/ticket_8412/parsed_logs.jsonl"
    if not os.path.exists(output_file):
        pytest.skip("Output file missing, skipping detailed checks.")

    expected_logs = [
        {"time": "2023-10-12 10:00:00", "level": "INFO", "message": "Service started successfully"},
        {"time": "2023-10-12 10:01:15", "level": "DEBUG", "message": "Connecting to database at localhost:5432"},
        {"time": "2023-10-12 10:02:30", "level": "ERROR", "message": "Connection lost - retrying in 5s"},
        {"time": "2023-10-12 10:05:00", "level": "WARN", "message": "[AuthService] Failed login attempt for user [admin]"},
        {"time": "2023-10-12 10:06:00", "level": "INFO", "message": "Service stopped"}
    ]

    with open(output_file, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == len(expected_logs), "The number of lines in the output file does not match the input logs."

    for i, expected in enumerate(expected_logs):
        actual = json.loads(lines[i])
        assert actual == expected, f"Log entry {i+1} does not match expected output.\nExpected: {expected}\nActual: {actual}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
