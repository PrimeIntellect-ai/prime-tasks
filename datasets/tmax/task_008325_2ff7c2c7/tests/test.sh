#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import subprocess
import sys
import tempfile

import pytest

SCRIPT = '/home/user/log_parser.py'
SERVER_LOG = '/home/user/server.log'
PARSED_LOG = '/home/user/parsed_logs.json'


def expected_parse(raw_bytes):
    parsed = []
    for line_num, raw_line in enumerate(raw_bytes.splitlines(keepends=True), 1):
        decoded = raw_line.decode('utf-8', errors='replace')
        tags = []
        i = 0
        while i < len(decoded):
            if decoded[i] == '[':
                end = decoded.find(']', i)
                if end == -1:
                    tags.append(decoded[i + 1:].rstrip())
                    break
                tags.append(decoded[i + 1:end])
                i = end + 1
            else:
                i += 1
        parsed.append({
            'line': line_num,
            'tags': tags,
            'raw': decoded.strip(),
        })
    return parsed


def run_parser(input_path, output_path):
    try:
        result = subprocess.run(
            [sys.executable, SCRIPT, input_path, output_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=5,
            check=False,
        )
    except subprocess.TimeoutExpired:
        pytest.fail('log_parser.py did not terminate within 5 seconds')

    assert result.returncode == 0, (
        f'log_parser.py exited with status {result.returncode}. '
        f'stdout={result.stdout!r}, stderr={result.stderr!r}'
    )
    assert os.path.isfile(output_path), f'Parser did not create {output_path}'

    try:
        with open(output_path, 'r', encoding='utf-8') as f:
            return json.load(f)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        pytest.fail(f'Parser output is not valid UTF-8 JSON: {exc}')


@pytest.fixture(scope='session', autouse=True)
def execute_submitted_parser():
    assert os.path.isfile(SCRIPT), f'File not found: {SCRIPT}'
    assert os.path.isfile(SERVER_LOG), f'File not found: {SERVER_LOG}'
    run_parser(SERVER_LOG, PARSED_LOG)


def test_debugging_notes():
    notes_path = '/home/user/debugging_notes.txt'
    assert os.path.isfile(notes_path), f"File not found: {notes_path}"

    with open(notes_path, 'r', encoding='utf-8') as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 2, f"Expected exactly 2 lines in debugging_notes.txt, found {len(lines)}"
    assert lines[0] == "3", f"Expected first line to be '3', got '{lines[0]}'"
    assert lines[1] == "5", f"Expected second line to be '5', got '{lines[1]}'"


def test_parsed_logs_json():
    json_path = '/home/user/parsed_logs.json'
    assert os.path.isfile(json_path), f"File not found: {json_path}"

    with open(json_path, 'r', encoding='utf-8') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {json_path} is not valid JSON.")

    assert isinstance(data, list), "Parsed JSON should be a list of objects."
    assert len(data) == 6, f"Expected 6 entries in JSON, found {len(data)}"

    # Check line 3 encoding fix
    line_3 = next((item for item in data if item.get("line") == 3), None)
    assert line_3 is not None, "Line 3 is missing from parsed_logs.json"
    assert "\ufffd" in line_3.get("raw", ""), "Line 3 'raw' field should contain the Unicode replacement character."

    # Check line 5 infinite loop fix
    line_5 = next((item for item in data if item.get("line") == 5), None)
    assert line_5 is not None, "Line 5 is missing from parsed_logs.json"
    tags_5 = line_5.get("tags", [])
    assert "unterminated string" in tags_5, f"Expected 'unterminated string' in line 5 tags, got {tags_5}"

    with open(SERVER_LOG, 'rb') as f:
        expected = expected_parse(f.read())
    assert data == expected, 'parsed_logs.json does not exactly represent server.log'


def test_parser_on_independent_input():
    sample = (
        b'plain text\n'
        b'[FIRST] middle [SECOND] end\n'
        b'[OPEN remainder with spaces   \r\n'
        b'invalid byte: \xfe and [tail without close\n'
        b'[OK] then [broken final tag\t  \n'
    )

    with tempfile.TemporaryDirectory() as tmpdir:
        input_path = os.path.join(tmpdir, 'challenge.log')
        output_path = os.path.join(tmpdir, 'challenge.json')
        with open(input_path, 'wb') as f:
            f.write(sample)

        actual = run_parser(input_path, output_path)

    assert actual == expected_parse(sample), (
        'log_parser.py failed independent encoding or malformed-tag cases'
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
