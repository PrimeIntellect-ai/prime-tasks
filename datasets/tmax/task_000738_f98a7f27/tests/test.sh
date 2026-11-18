#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import hashlib
import json
import os
import re
import secrets
import subprocess
import sys
import tokenize
from collections import defaultdict
from datetime import datetime, timedelta

import pytest

OUTPUT_PATH = "/home/user/anomalies.json"
LOG_PATH = "/home/user/system_events.log"


def test_anomalies_json_exists():
    """Test that the output file anomalies.json exists."""
    assert os.path.exists(OUTPUT_PATH), f"The file {OUTPUT_PATH} was not created."
    assert os.path.isfile(OUTPUT_PATH), f"The path {OUTPUT_PATH} is not a file."


def test_anomalies_json_content():
    """Test that anomalies.json contains the correct data."""
    with open(OUTPUT_PATH, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {OUTPUT_PATH} does not contain valid JSON.")

    assert isinstance(data, list), f"The root of the JSON file should be a list, got {type(data).__name__}."

    expected_data = [
        {"minute": "2023-10-24 10:05", "rolling_avg": 3.67},
        {"minute": "2023-10-24 10:06", "rolling_avg": 4.33},
        {"minute": "2023-10-24 10:07", "rolling_avg": 4.33}
    ]

    assert len(data) == len(expected_data), f"Expected {len(expected_data)} anomalies, but found {len(data)}."

    for i, expected_item in enumerate(expected_data):
        assert "minute" in data[i], f"Item at index {i} is missing the 'minute' key."
        assert "rolling_avg" in data[i], f"Item at index {i} is missing the 'rolling_avg' key."
        assert data[i]["minute"] == expected_item["minute"], f"Expected minute {expected_item['minute']} at index {i}, got {data[i]['minute']}."
        actual_avg = data[i]["rolling_avg"]
        expected_avg = expected_item["rolling_avg"]
        assert isinstance(actual_avg, (int, float)), f"rolling_avg at index {i} should be a number."
        assert abs(actual_avg - expected_avg) < 0.011, f"Expected rolling_avg {expected_avg} at index {i}, got {actual_avg}."


def _python_candidates():
    candidates = []
    for root, dirs, files in os.walk('/home/user'):
        dirs[:] = [d for d in dirs if not os.path.islink(os.path.join(root, d))]
        for name in files:
            path = os.path.join(root, name)
            if name.endswith('.py') and os.path.isfile(path) and not os.path.islink(path):
                candidates.append(path)
    return sorted(candidates)


def _is_streaming_sha256_script(path):
    try:
        with tokenize.open(path) as f:
            source = f.read()
        tree = ast.parse(source, filename=path)
    except (OSError, SyntaxError, UnicodeError):
        return False, "not a valid Python source file"

    calls = [node for node in ast.walk(tree) if isinstance(node, ast.Call)]
    forbidden = {'read', 'readlines', 'read_text', 'splitlines'}
    for call in calls:
        if isinstance(call.func, ast.Attribute) and call.func.attr in forbidden:
            return False, f"uses non-streaming {call.func.attr}()"

    has_line_loop = any(isinstance(node, (ast.For, ast.AsyncFor, ast.While)) for node in ast.walk(tree))
    if not has_line_loop:
        return False, "does not contain a line-processing loop"

    has_sha256 = False
    for call in calls:
        func = call.func
        if isinstance(func, ast.Name) and func.id == 'sha256':
            has_sha256 = True
        elif isinstance(func, ast.Attribute) and func.attr == 'sha256':
            has_sha256 = True
        elif ((isinstance(func, ast.Name) and func.id == 'new') or
              (isinstance(func, ast.Attribute) and func.attr == 'new')):
            if call.args and isinstance(call.args[0], ast.Constant) and str(call.args[0].value).lower() == 'sha256':
                has_sha256 = True
    if not has_sha256:
        return False, "does not compute SHA256 hashes"

    return True, ""


def _expected_from_lines(lines):
    counts = defaultdict(set)
    pattern = re.compile(r'^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}):\d{2}\] [^-]* - (.*)$')
    for line in lines:
        match = pattern.match(line.rstrip('\n'))
        assert match, f"Internal test fixture contains an invalid line: {line!r}"
        minute, message = match.groups()
        normalized = re.sub(r'[^a-z0-9 ]', '', message.lower())
        normalized = re.sub(r' +', ' ', normalized).strip()
        counts[datetime.strptime(minute, '%Y-%m-%d %H:%M')].add(
            hashlib.sha256(normalized.encode()).hexdigest()
        )

    first = min(counts)
    last = max(counts)
    unique_counts = {minute: len(values) for minute, values in counts.items()}
    expected = []
    current = first
    while current <= last:
        total = sum(unique_counts.get(current - timedelta(minutes=i), 0) for i in range(3))
        average = total / 3
        if average > 3.0:
            expected.append({
                'minute': current.strftime('%Y-%m-%d %H:%M'),
                'rolling_avg': round(average, 2),
            })
        current += timedelta(minutes=1)
    return expected


def _make_fixture():
    nonce = secrets.token_hex(6)
    base = datetime(2024, 1, 1) + timedelta(
        days=secrets.randbelow(500), minutes=secrets.randbelow(20 * 60)
    )
    base = base.replace(second=0, microsecond=0)
    events = {
        0: [
            f"Alpha-{nonce}!!", f" ALPHA{nonce} ",
            f"Beta--X{nonce}", f"Beta X{nonce}",
            f"Gamma   Ray {nonce}", f"gamma ray {nonce}",
            f"Delta_1{nonce}",
        ],
        1: [f"One {nonce}", f"Two {nonce}", f"Three {nonce}", f"Four {nonce}", f"Five {nonce}"],
        3: [f"Red {nonce}", f"Green {nonce}", f"Blue {nonce}", f"Gold {nonce}"],
    }
    lines = []
    for offset in sorted(events):
        minute = base + timedelta(minutes=offset)
        for second, message in enumerate(events[offset]):
            lines.append(f"[{minute.strftime('%Y-%m-%d %H:%M')}:{second:02d}] INFO - {message}\n")
    return lines


def _validate_output(expected):
    assert os.path.isfile(OUTPUT_PATH), "script did not create /home/user/anomalies.json"
    with open(OUTPUT_PATH, 'r') as f:
        data = json.load(f)
    assert isinstance(data, list), "dynamic output root is not a list"
    assert len(data) == len(expected), f"dynamic output has {len(data)} items; expected {len(expected)}"
    for index, item in enumerate(data):
        assert isinstance(item, dict), f"dynamic item {index} is not an object"
        assert set(item) == {'minute', 'rolling_avg'}, f"dynamic item {index} has incorrect keys"
        assert item['minute'] == expected[index]['minute']
        assert isinstance(item['rolling_avg'], (int, float)) and not isinstance(item['rolling_avg'], bool)
        assert abs(item['rolling_avg'] - expected[index]['rolling_avg']) < 0.011


def test_python_workflow_executes_streaming_algorithm():
    candidates = _python_candidates()
    assert candidates, "No Python script was created under /home/user."

    with open(LOG_PATH, 'rb') as f:
        original_log = f.read()
    with open(OUTPUT_PATH, 'rb') as f:
        original_output = f.read()

    errors = []
    try:
        lines = _make_fixture()
        expected = _expected_from_lines(lines)
        for candidate in candidates:
            suitable, reason = _is_streaming_sha256_script(candidate)
            if not suitable:
                errors.append(f"{candidate}: {reason}")
                continue
            try:
                with open(LOG_PATH, 'w') as f:
                    f.writelines(lines)
                if os.path.exists(OUTPUT_PATH):
                    os.remove(OUTPUT_PATH)
                result = subprocess.run(
                    [sys.executable, candidate], cwd='/home/user',
                    stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                    text=True, timeout=15
                )
                assert result.returncode == 0, f"exit code {result.returncode}: {result.stderr[-1000:]}"
                _validate_output(expected)
                return
            except Exception as exc:
                errors.append(f"{candidate}: {exc}")
        pytest.fail("No created Python script correctly processed a fresh randomized log. " + " | ".join(errors))
    finally:
        with open(LOG_PATH, 'wb') as f:
            f.write(original_log)
        with open(OUTPUT_PATH, 'wb') as f:
            f.write(original_output)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
