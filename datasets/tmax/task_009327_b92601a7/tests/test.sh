#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import sys
import json
import secrets
import subprocess
import pytest

FIXED_PATH = "/home/user/fixed_transformer.py"
INPUT_PATH = "/home/user/test_input.jsonl"
OUTPUT_PATH = "/home/user/test_output.jsonl"


def run_transformer(input_text):
    result = subprocess.run(
        [sys.executable, FIXED_PATH],
        input=input_text,
        text=True,
        capture_output=True,
        timeout=5,
        cwd="/home/user",
    )
    assert result.returncode == 0, (
        f"fixed_transformer.py exited with {result.returncode}: {result.stderr}"
    )

    parsed = []
    for i, line in enumerate(result.stdout.splitlines(), 1):
        if not line.strip():
            continue
        try:
            parsed.append(json.loads(line))
        except json.JSONDecodeError:
            pytest.fail(f"Transformer output line {i} is not valid JSON: {line}")
    return parsed


def test_fixed_transformer_exists():
    path = FIXED_PATH
    assert os.path.isfile(path), f"Expected {path} to exist."


def test_test_input_jsonl():
    path = INPUT_PATH
    assert os.path.isfile(path), f"Expected {path} to exist."

    with open(path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 3, f"Expected exactly 3 lines in {path}, found {len(lines)}."

    # Check Line 1
    try:
        obj1 = json.loads(lines[0])
        assert obj1.get("id") == 1, "First line of test_input.jsonl should be valid JSON with id=1."
    except json.JSONDecodeError:
        pytest.fail("First line of test_input.jsonl must be valid JSON.")

    # Check Line 2
    try:
        json.loads(lines[1])
        pytest.fail("Second line of test_input.jsonl must be invalid/corrupted JSON.")
    except json.JSONDecodeError:
        pass

    # Check Line 3
    try:
        obj3 = json.loads(lines[2])
        assert obj3.get("id") == 3, "Third line of test_input.jsonl should be valid JSON with id=3."
    except json.JSONDecodeError:
        pytest.fail("Third line of test_input.jsonl must be valid JSON.")


def test_test_output_jsonl():
    path = OUTPUT_PATH
    assert os.path.isfile(path), f"Expected {path} to exist."

    with open(path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 3, f"Expected exactly 3 lines in {path}, found {len(lines)}."

    # We expect valid JSON in the output
    parsed_output = []
    for i, line in enumerate(lines):
        try:
            parsed_output.append(json.loads(line))
        except json.JSONDecodeError:
            pytest.fail(f"Line {i+1} in {path} is not valid JSON: {line}")

    # Check contents
    assert parsed_output[0] == {"id": 1, "status": "processed"}, "First output line is incorrect."
    assert parsed_output[1] == {"error": "corrupted"}, "Second output line is incorrect."
    assert parsed_output[2] == {"id": 3, "status": "processed"}, "Third output line is incorrect."


def test_saved_output_was_produced_by_fixed_transformer():
    with open(INPUT_PATH, "r") as f:
        input_text = f.read()
    with open(OUTPUT_PATH, "r") as f:
        saved_output = [json.loads(line) for line in f if line.strip()]

    assert run_transformer(input_text) == saved_output


def test_corruption_does_not_discard_accumulated_records():
    base = secrets.randbelow(1_000_000_000) + 10_000
    ids = [base + i for i in range(4)]
    input_lines = [
        json.dumps({"id": ids[0]}),
        json.dumps({"id": ids[1]}),
        f'{{"id": {base + 100}, bad syntax}}',
        json.dumps({"id": ids[2]}),
        f'{{"id": {base + 101}, definitely invalid}}',
        json.dumps({"id": ids[3]}),
    ]
    expected = [
        {"id": ids[0], "status": "processed"},
        {"id": ids[1], "status": "processed"},
        {"error": "corrupted"},
        {"id": ids[2], "status": "processed"},
        {"error": "corrupted"},
        {"id": ids[3], "status": "processed"},
    ]

    assert run_transformer("\n".join(input_lines) + "\n") == expected
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
