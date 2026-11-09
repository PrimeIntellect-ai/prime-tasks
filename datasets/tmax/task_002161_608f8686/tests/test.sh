#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import re
import json
import random
import string
import subprocess
import pytest

ORACLE_PATH = "/tests/oracle_format_alert.py"
AGENT_PATH = "/home/user/format_alert.py"
EXTRACTED_ALERTS_PATH = "/home/user/extracted_alerts.txt"
VIDEO_PATH = "/app/security_feed.mp4"

def generate_random_string(length):
    return ''.join(random.choices(string.ascii_letters + string.digits, k=length))

def generate_random_ipv4():
    return f"{random.randint(1, 255)}.{random.randint(0, 255)}.{random.randint(0, 255)}.{random.randint(0, 255)}"

def generate_fuzz_inputs(n=1000, seed=42):
    random.seed(seed)
    inputs = []
    levels = ["INFO", "WARNING", "ERROR", "CRITICAL"]

    for _ in range(int(n * 0.7)):
        level = random.choice(levels)
        user = generate_random_string(8)
        action = generate_random_string(10)
        ip = generate_random_ipv4()
        payload = {"user": user, "action": action, "ip": ip, "extra": "data"}
        inputs.append(f"[{level}] {json.dumps(payload)}")

    for _ in range(n - int(n * 0.7)):
        choice = random.randint(1, 4)
        if choice == 1:
            # Malformed JSON
            inputs.append(f"[{random.choice(levels)}] {{\"user\": \"abc\", \"action\": \"def\"")
        elif choice == 2:
            # Missing key
            inputs.append(f"[{random.choice(levels)}] {{\"user\": \"abc\", \"action\": \"def\"}}")
        elif choice == 3:
            # Missing prefix
            payload = {"user": generate_random_string(8), "action": generate_random_string(10), "ip": generate_random_ipv4()}
            inputs.append(json.dumps(payload))
        else:
            # Garbage
            inputs.append(generate_random_string(random.randint(10, 150)))

    random.shuffle(inputs)
    return inputs

def run_script(script_path, input_str):
    result = subprocess.run(
        ["python3", script_path],
        input=input_str,
        text=True,
        capture_output=True
    )
    return result.stdout

def test_fuzz_equivalence():
    assert os.path.isfile(ORACLE_PATH), f"Oracle program missing at {ORACLE_PATH}"
    assert os.path.isfile(AGENT_PATH), f"Agent program missing at {AGENT_PATH}"

    with open(ORACLE_PATH, "rb") as f:
        oracle_bytes = f.read()
    with open(AGENT_PATH, "rb") as f:
        agent_bytes = f.read()
    assert agent_bytes != oracle_bytes, "Agent program must not be a byte-identical copy of the reference"

    inputs = generate_fuzz_inputs(1000)
    for i, inp in enumerate(inputs):
        oracle_out = run_script(ORACLE_PATH, inp)
        agent_out = run_script(AGENT_PATH, inp)

        assert oracle_out == agent_out, (
            f"Output mismatch on input {i}:\n"
            f"Input: {inp!r}\n"
            f"Oracle output: {oracle_out!r}\n"
            f"Agent output: {agent_out!r}"
        )

def test_extracted_alerts_file():
    assert os.path.isfile(EXTRACTED_ALERTS_PATH), f"Missing extracted alerts file at {EXTRACTED_ALERTS_PATH}"

    with open(EXTRACTED_ALERTS_PATH, "r") as f:
        content = f.read()

    alert_blocks = re.findall(r'ALERT LEVEL: \w+', content)
    assert len(alert_blocks) == 12, f"Expected exactly 12 alert blocks, found {len(alert_blocks)}"

    # Check for blank lines between blocks
    blocks = content.strip().split('\n\n')
    assert len(blocks) == 12, "Expected blank lines separating the 12 alert blocks"

    extracted = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", VIDEO_PATH, "-map", "0:s:0", "-f", "srt", "pipe:1"],
        text=True,
        capture_output=True,
        check=True,
    ).stdout
    log_lines = [line for line in extracted.splitlines() if line.startswith("[")]
    expected_blocks = []
    for line in log_lines:
        oracle_out = run_script(ORACLE_PATH, line)
        if oracle_out != "INVALID LOG\n":
            expected_blocks.append(oracle_out.rstrip("\n"))

    expected = "\n\n".join(expected_blocks)
    assert content.rstrip("\n") == expected, (
        "extracted_alerts.txt does not contain the correctly formatted valid "
        "subtitle log lines in source order"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
