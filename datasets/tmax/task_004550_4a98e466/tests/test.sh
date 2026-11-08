#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import string
import subprocess
import pytest


def generate_random_plate():
    pattern = random.choice(["[A-Z]{3}[0-9]{3}", "[A-Z]{2}[0-9]{4}", "UNKNOWN"])
    if pattern == "[A-Z]{3}[0-9]{3}":
        return "".join(random.choices(string.ascii_uppercase, k=3)) + "".join(random.choices(string.digits, k=3))
    elif pattern == "[A-Z]{2}[0-9]{4}":
        return "".join(random.choices(string.ascii_uppercase, k=2)) + "".join(random.choices(string.digits, k=4))
    return "UNKNOWN"


def generate_fuzz_input(num_lines):
    lines = []
    prev_line_data = None

    for _ in range(num_lines):
        if prev_line_data and random.random() < 0.3:
            epoch = prev_line_data['epoch'] + random.randint(0, 4000)
            event = prev_line_data['event']
            plate = prev_line_data['plate']
            speed = prev_line_data['speed']
        else:
            epoch = random.randint(1600000000000, 1600000500000)
            event = random.choice(["SPEEDING", "IDLE", "BRAKE", "CRASH"])
            plate = generate_random_plate()
            speed = random.randint(0, 120)

        lines.append(f"{epoch}|{event}|{plate}|{speed}")
        prev_line_data = {'epoch': epoch, 'event': event, 'plate': plate, 'speed': speed}

    return "\n".join(lines) + "\n"


def normalized_text(path):
    with open(path, 'r', encoding='utf-8', newline=None) as f:
        return f.read().replace('\r\n', '\n')


def test_extracted_logs_exist():
    path = '/home/user/extracted_logs.srt'
    assert os.path.isfile(path), "Part 1 failed: /home/user/extracted_logs.srt does not exist."

    expected_path = '/tmp/expected_extracted_logs.srt'
    subprocess.run(
        ['ffmpeg', '-v', 'error', '-y', '-i', '/app/telemetry_stream.mp4',
         '-map', '0:s:0', expected_path],
        check=True,
        capture_output=True,
        text=True,
    )
    assert normalized_text(path) == normalized_text(expected_path), \
        "Part 1 failed: extracted_logs.srt is not the subtitle track extracted from the supplied video."


def test_raw_telemetry_exists_and_content():
    raw_path = '/home/user/raw_telemetry.txt'
    assert os.path.isfile(raw_path), f"Part 1 failed: {raw_path} does not exist."

    with open(raw_path, 'r') as f:
        content = f.read().strip().split('\n')

    assert len(content) >= 4, "raw_telemetry.txt does not contain the expected number of lines."
    assert "1600000000000|SPEEDING|XYZ789|65" in content, "Expected telemetry line missing from raw_telemetry.txt"
    assert "1600000001500|SPEEDING|XYZ789|65" in content, "Expected telemetry line missing from raw_telemetry.txt"
    assert "1600000004000|BRAKE|ABC123|20" in content, "Expected telemetry line missing from raw_telemetry.txt"
    assert "1600000005000|BRAKE|A1B2C3|10" in content, "Expected telemetry line missing from raw_telemetry.txt"

    expected_srt = normalized_text('/tmp/expected_extracted_logs.srt')
    timestamp = re.compile(r'^\d{2}:\d{2}:\d{2},\d{3} --> \d{2}:\d{2}:\d{2},\d{3}$')
    expected_lines = []
    for line in expected_srt.splitlines():
        stripped = line.strip()
        if not stripped or stripped.isdigit() or timestamp.fullmatch(stripped):
            continue
        expected_lines.append(stripped)

    assert content == expected_lines, \
        "Part 1 failed: raw_telemetry.txt is not the cleaned content of the extracted subtitle track."


def test_process_telemetry_executable():
    script_path = '/home/user/process_telemetry.sh'
    assert os.path.isfile(script_path), f"Part 2 failed: {script_path} does not exist."
    assert not os.path.islink(script_path), f"Part 2 failed: {script_path} must be a submitted script, not a symbolic link."
    assert os.access(script_path, os.X_OK), f"Part 2 failed: {script_path} is not executable."


def test_fuzz_equivalence():
    oracle_path = '/tests/oracle_etl.sh'
    agent_path = '/home/user/process_telemetry.sh'

    assert os.path.isfile(oracle_path), "Oracle script missing."
    assert os.path.isfile(agent_path), "Agent script missing."

    with open(oracle_path, 'rb') as f:
        oracle_bytes = f.read()
    with open(agent_path, 'rb') as f:
        agent_bytes = f.read()
    assert agent_bytes != oracle_bytes, "Agent script must not be a byte-identical copy of the reference implementation."

    random.seed(42)
    cases = []
    for _ in range(200):
        num_lines = random.randint(20, 500)
        cases.append(generate_fuzz_input(num_lines))

    expected_outputs = []
    for i, input_data in enumerate(cases):
        oracle_proc = subprocess.run(
            ['bash', oracle_path], input=input_data, text=True, capture_output=True
        )
        assert oracle_proc.returncode == 0, f"Oracle failed on input {i}"
        expected_outputs.append(oracle_proc.stdout)

    # The reference is needed only to derive expected results. Remove it before
    # running the submission so the submitted script cannot delegate its work.
    os.unlink(oracle_path)

    for i, (input_data, expected_stdout) in enumerate(zip(cases, expected_outputs)):
        agent_proc = subprocess.run([agent_path], input=input_data, text=True, capture_output=True)

        if expected_stdout != agent_proc.stdout:
            error_msg = (
                f"Mismatch found on fuzz iteration {i}.\n"
                f"Input:\n{input_data[:200]}...\n\n"
                f"Oracle Output (first 200 chars):\n{expected_stdout[:200]}...\n\n"
                f"Agent Output (first 200 chars):\n{agent_proc.stdout[:200]}...\n"
            )
            pytest.fail(error_msg)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
