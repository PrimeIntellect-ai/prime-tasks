#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import re
import subprocess
import pytest

RAW_PATH = "/home/user/raw_logs.txt"
CLEAN_DATA_PATH = "/home/user/clean_data.jsonl"
ANOMALIES_PATH = "/home/user/anomalies.csv"

ORIGINAL_RAW = """[2023-10-01T10:00:01Z] INFO {"user": "alice", "msg": "hi", "declared_len": 2}
[2023-10-01T10:00:02Z] INFO {"user": "bob", "msg": "café", "declared_len": 4}
[2023-10-01T10:00:03Z] ERROR {"user": "sys", "msg": "fail", "declared_len": 4}
[2023-10-01T10:00:04Z] INFO {"user": "charlie", "msg": "こんにちは", "declared_len": 5}
[2023-10-01T10:00:05Z] INFO {"user": "dave", "msg": "🚀🚀🚀", "declared_len": 3}
[2023-10-01T10:00:06Z] INFO {"user": "eve", "msg": "hello", "declared_len": 99}
[2023-10-01T10:00:07Z] INFO {"user": "frank", "msg": "This is a very long message that should trigger the anomaly detector because it is much longer than the previous ones.", "declared_len": 118}
[2023-10-01T10:00:08Z] INFO {"user": "grace", "msg": "ok", "declared_len": 2}
"""

GENERATED_RAW = r"""[2040-02-03T04:05:01Z] INFO {"user": "α", "msg": "é", "declared_len": 1}
[2040-02-03T04:05:02Z] INFO {"user":"b","msg":"ab","declared_len":2}
[2040-02-03T04:05:03Z] ERROR {"user": "ignored", "msg": "xxxxxxxx", "declared_len": 8}
[2040-02-03T04:05:04Z] INFO {"user": "bad", "msg": "no", "declared_len": 9}
[2040-02-03T04:05:05Z] INFO {"user": "c", "msg": "🚀🚀🚀🚀🚀🚀", "declared_len": 6}
[2040-02-03T04:05:06Z] INFO {"user":"d","msg":"A\u0301","declared_len":2}
"""


def derive_expected(raw_text):
    clean = []
    anomalies = []
    valid_lengths = []

    for line in raw_text.splitlines():
        match = re.match(r"^\[([^\]]+)\]\s+(\S+)\s+(.*)$", line)
        if not match:
            continue
        timestamp, level, payload_text = match.groups()
        if level == "ERROR":
            continue
        try:
            payload = json.loads(payload_text)
        except json.JSONDecodeError:
            continue
        if not all(key in payload for key in ("user", "msg", "declared_len")):
            continue
        if not isinstance(payload["user"], str) or not isinstance(payload["msg"], str):
            continue
        if isinstance(payload["declared_len"], bool) or not isinstance(payload["declared_len"], int):
            continue

        current = payload["declared_len"]
        if len(payload["msg"]) != current:
            continue

        previous = valid_lengths[-4:]
        if previous and current > 2.0 * (sum(previous) / len(previous)):
            anomalies.append(f"{timestamp},{payload['user']},{current}")
        valid_lengths.append(current)
        clean.append(payload_text)

    return clean, ["timestamp,user,declared_len"] + anomalies


def reset_and_run(executable, raw_text):
    with open(RAW_PATH, "w", encoding="utf-8", newline="") as f:
        f.write(raw_text)
    for path in (CLEAN_DATA_PATH, ANOMALIES_PATH):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass
    result = subprocess.run(
        [executable], cwd="/home/user", stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, timeout=15
    )
    assert result.returncode == 0, (
        f"Compiled program exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


@pytest.fixture(scope="session")
def compiled_program():
    sources = []
    for extension in ("*.cpp", "*.cc", "*.cxx", "*.c++"):
        sources.extend(glob.glob(os.path.join("/home/user", extension)))
    sources = sorted(set(sources))
    assert sources, "No C++ source file was found in /home/user."

    commands = []
    if len(sources) > 1:
        commands.append(sources)
    commands.extend([[source] for source in sources])

    errors = []
    executable = "/tmp/submitted_etl"
    for source_group in commands:
        result = subprocess.run(
            ["g++", "-std=c++17", "-I/home/user", *source_group, "-o", executable],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=60
        )
        if result.returncode == 0:
            reset_and_run(executable, ORIGINAL_RAW)
            return executable
        errors.append(result.stderr)

    pytest.fail("Unable to compile the submitted C++ source.\n" + "\n".join(errors))


def read_exact_lines(path):
    assert os.path.exists(path), f"Output file {path} is missing."
    assert os.path.isfile(path), f"{path} is not a file."
    with open(path, "r", encoding="utf-8", newline="") as f:
        return f.read().splitlines()


def test_clean_data_exists_and_valid(compiled_program):
    expected_clean, _ = derive_expected(ORIGINAL_RAW)
    lines = read_exact_lines(CLEAN_DATA_PATH)

    clean_records = []
    for i, line in enumerate(lines):
        try:
            clean_records.append(json.loads(line))
        except json.JSONDecodeError:
            pytest.fail(f"Line {i+1} in {CLEAN_DATA_PATH} is not valid JSON: {line}")

    expected_users = ["alice", "bob", "charlie", "dave", "grace"]
    actual_users = [record.get("user") for record in clean_records]
    assert actual_users == expected_users, (
        f"Clean data does not contain the correct users in the correct order. "
        f"Expected {expected_users}, got {actual_users}."
    )
    assert lines == expected_clean, (
        "clean_data.jsonl must contain every valid original JSON payload exactly "
        "as it appeared in the input, in order."
    )


def test_anomalies_exists_and_valid(compiled_program):
    _, expected_anomalies = derive_expected(ORIGINAL_RAW)
    lines = read_exact_lines(ANOMALIES_PATH)
    assert len(lines) > 0, f"{ANOMALIES_PATH} is empty."
    assert lines[0] == "timestamp,user,declared_len", (
        f"Incorrect CSV header in {ANOMALIES_PATH}."
    )
    assert lines == expected_anomalies, (
        f"Anomalies data mismatch. Expected {expected_anomalies}, got {lines}."
    )


def test_program_processes_unicode_validation_and_anomalies(compiled_program):
    try:
        reset_and_run(compiled_program, GENERATED_RAW)
        expected_clean, expected_anomalies = derive_expected(GENERATED_RAW)
        assert read_exact_lines(CLEAN_DATA_PATH) == expected_clean
        assert read_exact_lines(ANOMALIES_PATH) == expected_anomalies
    finally:
        reset_and_run(compiled_program, ORIGINAL_RAW)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
