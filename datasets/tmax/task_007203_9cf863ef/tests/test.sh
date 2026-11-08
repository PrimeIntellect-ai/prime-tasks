#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import pytest

RAW_PATH = "/home/user/raw_logs.txt"
CLEAN_PATH = "/home/user/clean_logs.txt"
CONFIG_PATH = "/home/user/.config/metrics.ini"
PROCESS_PATH = "/home/user/process.sh"
ANSWER_PATH = "/home/user/answer.txt"

ORIGINAL_RAW = (
    b"2023-10-01T10:05:00Z svc status=200 bytes=1000\n"
    b"2023-10-01T10:01:00Z svc status=200 bytes=200\n"
    b"2023-10-01T10:03:00Z svc status=200 bytes=500\n"
    b"corrupted_line_with_binary_\x00\xff_garbage\n"
    b"2023-10-01T10:02:00Z svc status=200 bytes=400\n"
    b"2023-10-01T10:04:00Z svc status=200 bytes=100\n"
)


def expected_clean_lines():
    assert os.path.isfile(RAW_PATH), f"File {RAW_PATH} is missing."
    with open(RAW_PATH, "rb") as f:
        raw = f.read()
    assert raw == ORIGINAL_RAW, f"Input file {RAW_PATH} was modified."

    valid = []
    for line in raw.splitlines():
        try:
            line.decode("ascii")
        except UnicodeDecodeError:
            continue
        if line:
            valid.append(line)
    return sorted(valid, key=lambda line: line.split()[0])


def expected_result(lines, factor):
    values = []
    for line in lines:
        fields = line.decode("ascii").split()
        assert len(fields) >= 4, f"Line format incorrect: {line!r}"
        assert fields[3].startswith("bytes="), f"Line format incorrect: {line!r}"
        values.append(int(fields[3].split("=", 1)[1]))
    maximum = max(abs(current - previous) for previous, current in zip(values, values[1:]))
    return maximum * factor


def test_clean_logs_created_and_sorted():
    clean_logs_path = CLEAN_PATH
    assert os.path.isfile(clean_logs_path), f"File {clean_logs_path} is missing."

    with open(clean_logs_path, "rb") as f:
        content = f.read()

    # Check for non-ASCII characters
    try:
        text_content = content.decode('ascii')
    except UnicodeDecodeError:
        pytest.fail(f"File {clean_logs_path} contains non-ASCII characters.")

    lines = text_content.strip().split('\n')

    # Check if lines are sorted by timestamp
    timestamps = []
    for line in lines:
        if line.strip():
            parts = line.split()
            assert len(parts) >= 1, f"Line format incorrect: {line}"
            timestamps.append(parts[0])

    assert timestamps == sorted(timestamps), f"File {clean_logs_path} is not sorted chronologically."

    # Check if correct number of lines exist (5 valid lines from original)
    assert len(timestamps) == 5, f"Expected 5 clean log lines, found {len(timestamps)}."

    expected = expected_clean_lines()
    expected_content = b"\n".join(expected)
    assert content in (expected_content, expected_content + b"\n"), \
        f"File {clean_logs_path} does not contain exactly the valid records from {RAW_PATH} in chronological order."


def test_config_file_created_and_correct():
    config_path = CONFIG_PATH
    assert os.path.isfile(config_path), f"Configuration file {config_path} is missing."

    with open(config_path, "r") as f:
        content = f.read()

    # Remove whitespace/newlines to check assignment
    clean_content = content.replace(" ", "").replace("\"", "").replace("'", "").strip()
    assert "FACTOR=3" in clean_content.split('\n'), f"Configuration file {config_path} does not contain FACTOR=3."


def test_answer_file_correct():
    assert os.path.isfile(PROCESS_PATH), f"Calculation script {PROCESS_PATH} is missing."
    assert os.access(PROCESS_PATH, os.X_OK), f"Calculation script {PROCESS_PATH} is not executable."

    if os.path.exists(ANSWER_PATH):
        os.remove(ANSWER_PATH)
    completed = subprocess.run(
        [PROCESS_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert completed.returncode == 0, \
        f"Executing {PROCESS_PATH} failed with code {completed.returncode}: {completed.stderr}"

    answer_path = ANSWER_PATH
    assert os.path.isfile(answer_path), f"File {answer_path} is missing. Did you run process.sh?"

    with open(answer_path, "r") as f:
        content = f.read().strip()

    expected = str(expected_result(expected_clean_lines(), 3))
    assert content == expected, f"Expected derived answer {expected} in {answer_path}, but got {content}."
    assert content == "2700", f"Expected answer 2700 in {answer_path}, but got {content}."

    # The script must not replace or corrupt its required inputs.
    with open(CLEAN_PATH, "rb") as f:
        clean_after = f.read()
    expected_clean = b"\n".join(expected_clean_lines())
    assert clean_after in (expected_clean, expected_clean + b"\n")
    assert os.path.isfile(CONFIG_PATH)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
