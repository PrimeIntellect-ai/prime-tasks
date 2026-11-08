#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import stat
import string
import subprocess
import tempfile


def read_jsonl(path):
    with open(path, "r") as f:
        lines = f.read().strip().split("\n")

    parsed = []
    for i, line in enumerate(lines):
        try:
            parsed.append(json.loads(line))
        except json.JSONDecodeError:
            assert False, f"Line {i+1} in {path} is not valid JSON: {line}"
    return lines, parsed


def test_processed_logs_exist_and_correct():
    output_path = "/home/user/processed_logs.jsonl"
    assert os.path.exists(output_path), f"Output file {output_path} was not created."
    assert os.path.isfile(output_path), f"{output_path} should be a file."

    expected_lines = [
        {"level": "INFO", "user_id": "101", "action": "login"},
        {"level": "WARN", "user_id": "102", "action": "upload"},
        {"level": "ERROR", "user_id": "103", "action": "delete"},
        {"level": "INFO", "user_id": "104", "action": "logout"},
    ]

    with open(output_path, "r") as f:
        lines = f.read().strip().split("\n")

    assert len(lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in {output_path}, but found {len(lines)}."

    for i, (actual_line, expected_json) in enumerate(zip(lines, expected_lines)):
        try:
            actual_json = json.loads(actual_line)
        except json.JSONDecodeError:
            assert False, f"Line {i+1} in {output_path} is not valid JSON: {actual_line}"

        assert actual_json == expected_json, f"Line {i+1} does not match expected output.\nExpected: {expected_json}\nActual: {actual_json}"


def test_processor_builds_and_generates_correct_output():
    source = "/home/user/processor.go"
    assert os.path.exists(source), f"Go source {source} does not exist."
    mode = os.stat(source, follow_symlinks=False).st_mode
    assert stat.S_ISREG(mode), f"{source} must be a regular Go source file."

    with tempfile.TemporaryDirectory() as td:
        binary = os.path.join(td, "processor")
        build = subprocess.run(
            ["go", "build", "-o", binary, source],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=60,
        )
        assert build.returncode == 0, f"processor.go failed to build:\n{build.stdout}{build.stderr}"
        assert os.path.isfile(binary), "Go build did not produce an executable."

        original_output = os.path.join(td, "original.jsonl")
        run = subprocess.run(
            [binary, "/home/user/raw_logs.txt", original_output],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
        )
        assert run.returncode == 0, f"Built processor failed on raw_logs.txt:\n{run.stdout}{run.stderr}"
        _, original_actual = read_jsonl(original_output)
        original_expected = [
            {"level": "INFO", "user_id": "101", "action": "login"},
            {"level": "WARN", "user_id": "102", "action": "upload"},
            {"level": "ERROR", "user_id": "103", "action": "delete"},
            {"level": "INFO", "user_id": "104", "action": "logout"},
        ]
        assert original_actual == original_expected, "Built processor produced incorrect output for raw_logs.txt."

        rng = random.SystemRandom()
        records = []
        raw_lines = []
        for _ in range(7):
            level = rng.choice(["INFO", "WARN", "ERROR", "DEBUG"])
            user_id = str(rng.randrange(10000, 99999999))
            action = "act" + "".join(rng.choice(string.ascii_lowercase) for _ in range(12))
            raw_lines.append(f"[{level}] user:{user_id} action:{action}")
            records.append({"level": level, "user_id": user_id, "action": action})

        dynamic_input = os.path.join(td, "dynamic_logs.txt")
        dynamic_output = os.path.join(td, "dynamic_output.jsonl")
        with open(dynamic_input, "w") as f:
            f.write("\n".join(raw_lines) + "\n")

        run = subprocess.run(
            [binary, dynamic_input, dynamic_output],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
        )
        assert run.returncode == 0, f"Built processor failed on generated input:\n{run.stdout}{run.stderr}"
        assert os.path.isfile(dynamic_output), "Processor did not create its requested output file."
        lines, actual = read_jsonl(dynamic_output)
        assert len(lines) == len(records), f"Expected {len(records)} generated output lines, found {len(lines)}."
        assert actual == records, f"Processor produced incorrect output for generated input.\nExpected: {records}\nActual: {actual}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
