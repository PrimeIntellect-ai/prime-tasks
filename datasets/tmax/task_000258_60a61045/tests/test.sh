#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import stat
import struct
import subprocess

import pytest

SCRIPT_PATH = "/home/user/process_api.py"
JSON_PATH = "/home/user/api_test.json"
PAYLOAD_PATH = "/home/user/api_payload.bin"
STATE_PATH = "/home/user/final_state.txt"


def run_submission():
    assert os.path.isfile(SCRIPT_PATH), f"Missing required script {SCRIPT_PATH}"
    assert stat.S_ISREG(os.stat(SCRIPT_PATH).st_mode), f"{SCRIPT_PATH} is not a regular file"
    result = subprocess.run(
        ["python3", SCRIPT_PATH],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"{SCRIPT_PATH} failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


@pytest.fixture(scope="session", autouse=True)
def execute_submission():
    run_submission()


def compute_expected_state():
    json_path = "/home/user/api_test.json"
    assert os.path.isfile(json_path), f"Missing {json_path}"

    with open(json_path, "r") as f:
        data = json.load(f)

    instructions = data.get("instructions", [])

    bytecode = bytearray()
    stack = []

    for instr in instructions:
        parts = instr.strip().split()
        op = parts[0]
        if op == "PUSH":
            val = int(parts[1])
            bytecode.append(0x01)
            bytecode.extend(struct.pack("<H", val))
            stack.append(val)
        elif op == "ADD":
            bytecode.append(0x02)
            b = stack.pop()
            a = stack.pop()
            stack.append(a + b)
        elif op == "SUB":
            bytecode.append(0x03)
            b = stack.pop()
            a = stack.pop()
            stack.append(a - b)
        elif op == "MUL":
            bytecode.append(0x04)
            b = stack.pop()
            a = stack.pop()
            stack.append(a * b)

    final_val = stack[-1] if stack else None
    return bytes(bytecode), final_val


def test_api_payload_bin():
    payload_path = "/home/user/api_payload.bin"
    assert os.path.isfile(payload_path), f"File {payload_path} is missing. Did the script run and create it?"

    expected_bytes, _ = compute_expected_state()

    with open(payload_path, "rb") as f:
        actual_bytes = f.read()

    assert actual_bytes == expected_bytes, f"Binary payload in {payload_path} does not match expected bytecode."


def test_final_state_txt():
    state_path = "/home/user/final_state.txt"
    assert os.path.isfile(state_path), f"File {state_path} is missing. Did the script run and create it?"

    _, expected_val = compute_expected_state()

    with open(state_path, "r") as f:
        actual_val_str = f.read().strip()

    assert actual_val_str == str(expected_val), f"Final state in {state_path} is '{actual_val_str}', expected '{expected_val}'."


def expected_for(instructions):
    bytecode = bytearray()
    stack = []
    for instruction in instructions:
        parts = instruction.split()
        if parts[0] == "PUSH":
            value = int(parts[1])
            bytecode.append(0x01)
            bytecode.extend(struct.pack("<H", value))
            stack.append(value)
        elif parts[0] == "ADD":
            bytecode.append(0x02)
            b = stack.pop()
            a = stack.pop()
            stack.append(a + b)
        elif parts[0] == "SUB":
            bytecode.append(0x03)
            b = stack.pop()
            a = stack.pop()
            stack.append(a - b)
        elif parts[0] == "MUL":
            bytecode.append(0x04)
            b = stack.pop()
            a = stack.pop()
            stack.append(a * b)
    return bytes(bytecode), stack[-1]


def read_if_present(path):
    if not os.path.lexists(path):
        return None
    with open(path, "rb") as f:
        return f.read()


def restore_file(path, contents):
    if os.path.lexists(path):
        os.unlink(path)
    if contents is not None:
        with open(path, "wb") as f:
            f.write(contents)


def test_script_handles_unseen_instruction_sequences():
    original_json = read_if_present(JSON_PATH)
    original_payload = read_if_present(PAYLOAD_PATH)
    original_state = read_if_present(STATE_PATH)

    values = [secrets.randbelow(60000) + 1 for _ in range(12)]
    cases = [
        [f"PUSH {values[0]}", f"PUSH {values[1]}", "ADD"],
        [f"PUSH {values[2]}", f"PUSH {values[3]}", "SUB"],
        [f"PUSH {values[4]}", f"PUSH {values[5]}", "MUL"],
        [
            f"PUSH {values[6]}",
            f"PUSH {values[7]}",
            "ADD",
            f"PUSH {values[8]}",
            "MUL",
            f"PUSH {values[9]}",
            "SUB",
            f"PUSH {values[10]}",
            f"PUSH {values[11]}",
            "ADD",
            "ADD",
        ],
    ]

    try:
        for instructions in cases:
            with open(JSON_PATH, "w") as f:
                json.dump({"instructions": instructions}, f)

            for output_path in (PAYLOAD_PATH, STATE_PATH):
                if os.path.lexists(output_path):
                    os.unlink(output_path)

            run_submission()
            expected_payload, expected_state = expected_for(instructions)

            assert os.path.isfile(PAYLOAD_PATH), "Script did not recreate api_payload.bin"
            assert os.path.isfile(STATE_PATH), "Script did not recreate final_state.txt"
            with open(PAYLOAD_PATH, "rb") as f:
                assert f.read() == expected_payload, "Payload is incorrect for an unseen instruction sequence"
            with open(STATE_PATH, "r") as f:
                assert f.read().strip() == str(expected_state), "Emulated result is incorrect for an unseen instruction sequence"
    finally:
        restore_file(JSON_PATH, original_json)
        restore_file(PAYLOAD_PATH, original_payload)
        restore_file(STATE_PATH, original_state)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
