#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import subprocess
import tempfile

REPO_DIR = "/home/user/tlv_processor"
EXPECTED_OUTPUT = b"String: Hello\nPadding/Metadata (0 bytes)\nString: World\n"


def test_bug_report_exists_and_valid():
    report_path = "/home/user/bug_report.json"
    assert os.path.isfile(report_path), f"Bug report {report_path} is missing."

    with open(report_path, "r") as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            assert False, f"{report_path} is not valid JSON."

    assert "bad_commit_hash" in report, "Missing 'bad_commit_hash' in bug report."
    assert "buggy_function_name" in report, "Missing 'buggy_function_name' in bug report."
    assert "decoded_payload_length" in report, "Missing 'decoded_payload_length' in bug report."

    assert report["buggy_function_name"] == "process_tlv", "Incorrect 'buggy_function_name' in bug report."

    output_path = "/home/user/decoded_output.txt"
    assert os.path.isfile(output_path), f"Decoded output {output_path} is missing."
    actual_length = os.path.getsize(output_path)
    assert type(report["decoded_payload_length"]) is int, "'decoded_payload_length' must be an integer."
    assert report["decoded_payload_length"] == actual_length, (
        f"Incorrect 'decoded_payload_length'. Expected {actual_length}, "
        f"got {report['decoded_payload_length']}."
    )

    result = subprocess.run(
        ["git", "log", "--all", "--grep=Optimize metadata processing", "--format=%H"],
        cwd=REPO_DIR, capture_output=True, text=True
    )
    expected_hash = result.stdout.strip()
    assert expected_hash, "Could not find the expected commit in the git history."
    assert len(expected_hash.splitlines()) == 1, "Expected exactly one offending commit."
    assert report["bad_commit_hash"] == expected_hash, (
        f"Incorrect 'bad_commit_hash'. Expected {expected_hash}, got {report['bad_commit_hash']}."
    )


def test_decoded_output():
    output_path = "/home/user/decoded_output.txt"
    assert os.path.isfile(output_path), f"Decoded output {output_path} is missing."
    with open(output_path, "rb") as f:
        actual_output = f.read()
    assert actual_output == EXPECTED_OUTPUT, "The decoded output does not match the expected output."


def decode_expected(data):
    result = bytearray()
    i = 0
    while i < len(data):
        if i + 2 > len(data):
            break
        tlv_type = data[i]
        length = data[i + 1]
        if i + 2 + length > len(data):
            break
        value = data[i + 2:i + 2 + length]
        if tlv_type == 0x01:
            result.extend(b"String: " + value + b"\n")
        elif tlv_type == 0xFF:
            result.extend(f"Padding/Metadata ({length} bytes)\n".encode())
        else:
            result.extend(f"Unknown type {tlv_type:02X}\n".encode())
        i += 2 + length
    return bytes(result)


def run_decoder(payload):
    with tempfile.NamedTemporaryFile(prefix="tlv_case_", delete=False) as f:
        f.write(payload)
        path = f.name
    try:
        result = subprocess.run(
            ["./tlv_decoder", path], cwd=REPO_DIR,
            capture_output=True, timeout=5
        )
    finally:
        os.unlink(path)
    assert result.returncode == 0, f"The tlv_decoder failed with status {result.returncode}."
    assert result.stdout == decode_expected(payload), (
        f"Incorrect output for payload {payload.hex()}: {result.stdout!r}"
    )


def test_tlv_processor_fixed():
    make_result = subprocess.run(
        ["make", "-B"], cwd=REPO_DIR, capture_output=True, text=True
    )
    assert make_result.returncode == 0, f"Compilation failed:\n{make_result.stderr}"

    payload_path = "/home/user/payload.bin"
    run_result = subprocess.run(
        ["./tlv_decoder", payload_path], cwd=REPO_DIR,
        capture_output=True, timeout=5
    )
    assert run_result.returncode == 0, "The tlv_decoder failed to execute successfully."
    assert run_result.stdout == EXPECTED_OUTPUT, "The tlv_decoder output is incorrect, the bug might not be fully fixed."


def test_additional_tlv_inputs():
    cases = [
        bytes([0xFF, 0x00, 0x01, 0x01]) + b"A",
        bytes([0x01, 0x01]) + b"X" + bytes([0xFF, 0x00, 0xFF, 0x00, 0x02, 0x02]) + b"yz",
        bytes([0xFF, 0x03]) + b"abc" + bytes([0x01, 0x03]) + b"end",
        bytes([0x10, 0x02]) + b"qq" + bytes([0xFF, 0x00, 0x01, 0x02]) + b"ok",
    ]

    rng = random.Random(928451)
    for _ in range(12):
        payload = bytearray([0xFF, 0x00])
        for _ in range(rng.randint(2, 8)):
            tlv_type = rng.choice([0x01, 0xFF, 0x02, 0x10, 0xFE])
            length = rng.randint(0, 8)
            if tlv_type == 0x01:
                value = bytes(rng.choice(b"abcdefghijklmnopqrstuvwxyz") for _ in range(length))
            else:
                value = bytes(rng.randrange(256) for _ in range(length))
            payload.extend([tlv_type, length])
            payload.extend(value)
        payload.extend([0x01, 0x03])
        payload.extend(b"fin")
        cases.append(bytes(payload))

    for payload in cases:
        run_decoder(payload)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
