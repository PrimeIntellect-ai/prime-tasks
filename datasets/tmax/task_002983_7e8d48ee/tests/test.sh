#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import secrets
import subprocess
import tempfile

PROCESSOR_DIR = "/home/user/log_processor"
PARSER = os.path.join(PROCESSOR_DIR, "parser.js")
APP = os.path.join(PROCESSOR_DIR, "app.py")
LOG_DIR = os.path.join(PROCESSOR_DIR, "logs")
OUTPUT_FILE = os.path.join(PROCESSOR_DIR, "output.json")


def parse_expected_logs():
    expected = []
    for filename in sorted(os.listdir(LOG_DIR)):
        if not filename.endswith(".log"):
            continue
        with open(os.path.join(LOG_DIR, filename), "r", encoding="utf-8") as f:
            content = f.read().strip().split("\n")
        for line in content:
            if not line:
                continue
            match = re.match(r"^\[(.*?)\]\s+(\w+)\s+(.*)$", line)
            if match:
                expected.append({
                    "timestamp": match.group(1),
                    "level": match.group(2),
                    "message": match.group(3),
                })
    return expected


def test_parser_executes_and_escapes_edge_cases():
    assert os.path.isfile(PARSER), f"Parser {PARSER} is missing or is not a file."

    token = secrets.token_hex(16)
    messages = [
        f'Random {token}: user said "admin" and used C:\\temp\\input',
        f"Unicode café Ω {token} with a tab\tinside",
    ]
    fixture = (
        f"[2099-12-31 23:59:58] ERROR {messages[0]}\n"
        f"[2099-12-31 23:59:59] WARN {messages[1]}\n"
    )
    expected = [
        {"timestamp": "2099-12-31 23:59:58", "level": "ERROR", "message": messages[0]},
        {"timestamp": "2099-12-31 23:59:59", "level": "WARN", "message": messages[1]},
    ]

    with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", suffix=".log", delete=False) as f:
        f.write(fixture)
        fixture_path = f.name
    try:
        result = subprocess.run(
            ["node", PARSER, fixture_path],
            capture_output=True,
            text=True,
            timeout=10,
        )
    finally:
        os.unlink(fixture_path)

    assert result.returncode == 0, f"parser.js failed: {result.stderr}"
    try:
        parsed = json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        raise AssertionError(f"parser.js emitted invalid JSON: {result.stdout!r}") from exc
    assert parsed == expected, f"parser.js returned incorrect parsed data: {parsed!r}"


def test_app_generates_complete_exact_output():
    assert os.path.isfile(APP), f"Application {APP} is missing or is not a file."
    expected = parse_expected_logs()

    if os.path.exists(OUTPUT_FILE):
        assert os.path.isfile(OUTPUT_FILE), f"{OUTPUT_FILE} is not a regular file."
        os.remove(OUTPUT_FILE)

    result = subprocess.run(
        ["python3", APP],
        cwd=PROCESSOR_DIR,
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"app.py did not complete successfully. stdout={result.stdout!r} stderr={result.stderr!r}"
    )

    assert os.path.isfile(OUTPUT_FILE), f"Output file {OUTPUT_FILE} is missing. Did you run app.py successfully?"
    with open(OUTPUT_FILE, "r", encoding="utf-8") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as exc:
            raise AssertionError(f"File {OUTPUT_FILE} does not contain valid JSON.") from exc

    assert isinstance(data, list), f"Expected {OUTPUT_FILE} to contain a JSON array."
    assert len(data) == 20, f"Expected exactly 20 elements in {OUTPUT_FILE}, but found {len(data)}."
    assert data == expected, "output.json does not exactly match the entries derived from all source log files."

    edge_case_found = False
    for entry in data:
        if entry.get("message") == 'Failed to parse user input "admin" from payload':
            edge_case_found = True
            break
    assert edge_case_found, "The edge case message with double quotes was not found or not parsed correctly in output.json."


def test_resolution_txt_correct():
    resolution_file = "/home/user/resolution.txt"
    assert os.path.isfile(resolution_file), f"Resolution file {resolution_file} is missing."

    with open(resolution_file, "r", encoding="utf-8") as f:
        lines = f.read().splitlines()

    assert len(lines) == 2, f"Expected exactly 2 lines in {resolution_file}, but found {len(lines)}."
    assert lines[0] == "server_07.log", f"Expected the first line of {resolution_file} to be 'server_07.log', but got '{lines[0]}'."
    assert lines[1] == "SUCCESS", f"Expected the second line of {resolution_file} to be 'SUCCESS', but got '{lines[1]}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
