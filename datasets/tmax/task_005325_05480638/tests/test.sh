#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import shlex
import subprocess
import sys
import uuid

SCRIPT_PATH = "/home/user/process_traffic.py"
TRAFFIC_PATH = "/home/user/traffic.log"
OUTPUT_PATH = "/home/user/redacted_payloads.txt"
C2_IP = "203.0.113.88"
TOKEN = "Auth-99b-XYZ"


def run_processor():
    if os.path.exists(OUTPUT_PATH):
        os.unlink(OUTPUT_PATH)
    result = subprocess.run(
        [sys.executable, SCRIPT_PATH],
        cwd="/home/user",
        text=True,
        capture_output=True,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"{SCRIPT_PATH} failed with exit code {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.exists(OUTPUT_PATH), f"Missing required output file: {OUTPUT_PATH}"


def read_nonempty_output_lines():
    with open(OUTPUT_PATH, "r") as f:
        return [line.strip() for line in f if line.strip()]


def test_process_traffic_script_exists_and_behaves():
    """The submitted Python artifact must process both the supplied and fresh traffic."""
    assert os.path.exists(SCRIPT_PATH), f"Missing required script: {SCRIPT_PATH}"
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} should be a file"

    with open(TRAFFIC_PATH, "rb") as f:
        original_traffic = f.read()

    try:
        # Execute the artifact on the original traffic before checking the original assertion.
        run_processor()
        lines = read_nonempty_output_lines()
        expected_lines = [
            "User data: SSN 123-45-REDACTED found.",
            "More data, SSN 555-66-REDACTED and 888-99-REDACTED.",
        ]
        assert len(lines) == len(expected_lines), (
            f"Expected {len(expected_lines)} lines in {OUTPUT_PATH}, got {len(lines)}"
        )
        for i, (actual, expected) in enumerate(zip(lines, expected_lines)):
            assert actual == expected, (
                f"Line {i+1} mismatch.\nExpected: {expected}\nGot: {actual}"
            )

        # Exercise the script on unpredictable bodies and SSNs so fixed output cannot pass.
        def ssn():
            return f"{random.randint(100, 999)}-{random.randint(10, 99)}-{random.randint(1000, 9999)}"

        marker = uuid.uuid4().hex
        valid_bodies = [
            f"case-{marker}: primary {ssn()} and secondary {ssn()}.",
            f"plain matching payload {marker} with no sensitive number",
            f"prefix{ssn()}suffix / {ssn()} / end-{marker}",
        ]
        records = [
            {"method": "POST", "ip": C2_IP, "headers": {"X-Auth-Token": TOKEN}, "body": valid_bodies[0]},
            {"method": "POST", "ip": C2_IP, "headers": {"X-Auth-Token": "wrong-" + marker}, "body": f"decoy {ssn()}"},
            {"method": "GET", "ip": C2_IP, "headers": {"X-Auth-Token": TOKEN}, "body": f"decoy {ssn()}"},
            {"method": "POST", "ip": "198.51.100.42", "headers": {"X-Auth-Token": TOKEN}, "body": f"decoy {ssn()}"},
            {"method": "POST", "ip": C2_IP, "headers": {"Other": marker, "X-Auth-Token": TOKEN}, "body": valid_bodies[1]},
            {"method": "POST", "ip": C2_IP, "headers": {"X-Auth-Token": TOKEN}, "body": valid_bodies[2]},
        ]
        random.shuffle(records)
        expected_dynamic = [
            re.sub(r"(\d{3}-\d{2})-\d{4}", r"\1-REDACTED", record["body"])
            for record in records
            if record["method"] == "POST"
            and record["ip"] == C2_IP
            and record["headers"].get("X-Auth-Token") == TOKEN
        ]

        with open(TRAFFIC_PATH, "w") as f:
            for record in records:
                f.write(json.dumps(record) + "\n")

        run_processor()
        with open(OUTPUT_PATH, "r") as f:
            actual_dynamic = f.read().splitlines()
        assert actual_dynamic == expected_dynamic, (
            f"Processor output was incorrect for fresh traffic.\n"
            f"Expected: {expected_dynamic!r}\nGot: {actual_dynamic!r}"
        )
    finally:
        with open(TRAFFIC_PATH, "wb") as f:
            f.write(original_traffic)


def test_block_c2_script_valid():
    """The firewall artifact must be executable and contain exactly one valid rule command."""
    script_path = "/home/user/block_c2.sh"
    assert os.path.exists(script_path), f"Missing required script: {script_path}"
    assert os.path.isfile(script_path), f"{script_path} should be a file"
    assert os.access(script_path, os.X_OK), f"{script_path} is not executable. Did you run chmod +x?"

    with open(script_path, "r") as f:
        content = f.read()

    # Preserve the original component assertions.
    assert "iptables" in content, f"Script {script_path} must contain 'iptables' command"
    assert "OUTPUT" in content, f"Script {script_path} must target the 'OUTPUT' chain"
    assert C2_IP in content, f"Script {script_path} must target the C2 IP '{C2_IP}'"
    assert "DROP" in content, f"Script {script_path} must 'DROP' the traffic"

    syntax = subprocess.run(["bash", "-n", script_path], text=True, capture_output=True)
    assert syntax.returncode == 0, f"Invalid shell syntax in {script_path}: {syntax.stderr}"

    normalized = content.replace("\\\n", " ")
    command_lines = []
    for raw_line in normalized.splitlines():
        stripped = raw_line.strip()
        if not stripped or stripped.startswith("#!") or stripped.startswith("#"):
            continue
        tokens = shlex.split(stripped, comments=True, posix=True)
        if tokens:
            command_lines.append(tokens)

    assert len(command_lines) == 1, (
        f"{script_path} must contain exactly one command; found {len(command_lines)}"
    )
    tokens = command_lines[0]
    assert len(tokens) == 7, "Firewall command must consist only of iptables and three option/value pairs"
    assert os.path.basename(tokens[0]) == "iptables", "The sole command must be iptables"

    pairs = list(zip(tokens[1::2], tokens[2::2]))
    action_pairs = [(flag, value) for flag, value in pairs if flag in ("-A", "--append", "-I", "--insert")]
    destination_pairs = [(flag, value) for flag, value in pairs if flag in ("-d", "--destination")]
    jump_pairs = [(flag, value) for flag, value in pairs if flag in ("-j", "--jump")]

    assert len(action_pairs) == 1 and action_pairs[0][1] == "OUTPUT", "iptables rule must target the OUTPUT chain"
    assert len(destination_pairs) == 1 and destination_pairs[0][1] == C2_IP, f"iptables destination must be {C2_IP}"
    assert len(jump_pairs) == 1 and jump_pairs[0][1] == "DROP", "iptables rule must jump to DROP"
    assert len(action_pairs) + len(destination_pairs) + len(jump_pairs) == len(pairs), (
        "Firewall command contains unsupported or extra arguments"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
