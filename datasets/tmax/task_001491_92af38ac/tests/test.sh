#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import filecmp
import os
import random
import subprocess
import urllib.parse
import urllib.request

import pytest
import redis

ORACLE_PATH = "/opt/oracle/decoder_oracle"
AGENT_PROGRAM = "/home/user/decoder"
SOURCE_PATH = "/home/user/decoder.c"
MAKEFILE_PATH = "/home/user/Makefile"
ITERATIONS = 100


def encode_input(target_id, raw_bytes):
    encoded = urllib.parse.quote(base64.b64encode(raw_bytes), safe="")
    return f"patch://{target_id}/{encoded}"


def expected_result(target_id, raw_bytes):
    result = bytearray()
    assert len(raw_bytes) % 2 == 0

    for index in range(0, len(raw_bytes), 2):
        command = raw_bytes[index]
        value = raw_bytes[index + 1]
        if command == ord("I"):
            result.append(value)
        elif command == ord("D"):
            if result:
                result.pop()
        elif command == ord("R"):
            if result:
                result[-1] = value
        else:
            raise AssertionError(f"Invalid generated command: {command}")

    return f"TARGET={target_id} RESULT={result.decode('ascii')}\n"


def generate_random_case():
    target_id = chr(random.randint(65, 90))
    num_commands = random.randint(1, 15)
    raw_bytes = bytearray()

    for _ in range(num_commands):
        command = random.choice(["I", "D", "R"])
        if command == "I":
            raw_bytes.extend(b"I" + bytes([random.randint(32, 126)]))
        elif command == "D":
            raw_bytes.extend(b"D\x00")
        else:
            raw_bytes.extend(b"R" + bytes([random.randint(32, 126)]))

    return target_id, bytes(raw_bytes)


def run_decoder(target_id, raw_bytes):
    test_input = encode_input(target_id, raw_bytes)
    proc = subprocess.run(
        [AGENT_PROGRAM, test_input],
        capture_output=True,
        text=True,
        timeout=5,
    )
    assert proc.returncode == 0, (
        f"Decoder returned {proc.returncode} on {test_input}: {proc.stderr}"
    )
    assert proc.stdout == expected_result(target_id, raw_bytes), (
        f"Incorrect stdout on {test_input}. Expected "
        f"{expected_result(target_id, raw_bytes)!r}, got {proc.stdout!r}"
    )


def test_build_artifacts():
    assert os.path.isfile(SOURCE_PATH), f"Missing source file at {SOURCE_PATH}"
    assert os.path.isfile(MAKEFILE_PATH), f"Missing Makefile at {MAKEFILE_PATH}"

    build = subprocess.run(
        ["make", "-B", "-C", "/home/user"],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert build.returncode == 0, f"Makefile build failed:\n{build.stdout}\n{build.stderr}"
    assert os.path.isfile(AGENT_PROGRAM), f"Missing decoder at {AGENT_PROGRAM}"
    assert os.access(AGENT_PROGRAM, os.X_OK), "decoder is not executable"

    with open(AGENT_PROGRAM, "rb") as executable:
        assert executable.read(4) == b"\x7fELF", "decoder is not a compiled ELF executable"

    assert os.path.exists(ORACLE_PATH), f"Oracle missing at {ORACLE_PATH}"
    assert not filecmp.cmp(AGENT_PROGRAM, ORACLE_PATH, shallow=False), (
        "Submitted decoder is byte-identical to the shipped oracle"
    )


def test_fuzz_equivalence_to_specification():
    random.seed(42)

    fixed_cases = [
        ("A", b"IAIBRZD\x00IC"),
        ("M", b"D\x00RxI!R?"),
        ("Z", b"I I~D\x00I+I/"),
    ]
    for target_id, raw_bytes in fixed_cases:
        run_decoder(target_id, raw_bytes)

    for _ in range(ITERATIONS):
        target_id, raw_bytes = generate_random_case()
        run_decoder(target_id, raw_bytes)


def test_exactly_one_argument_required():
    no_arg = subprocess.run([AGENT_PROGRAM], capture_output=True, timeout=5)
    extra_arg = subprocess.run(
        [AGENT_PROGRAM, encode_input("A", b"IA"), "extra"],
        capture_output=True,
        timeout=5,
    )
    assert no_arg.returncode != 0, "decoder accepted no URL argument"
    assert extra_arg.returncode != 0, "decoder accepted more than one argument"


def test_end_to_end_service():
    target_id = "Q"
    raw_bytes = b"IAIBRxD\x00IC"
    expected = expected_result(target_id, raw_bytes)
    encoded = urllib.parse.quote(base64.b64encode(raw_bytes), safe="")
    url = f"http://localhost:8080/process/{target_id}/{encoded}"

    try:
        req = urllib.request.Request(url, method="GET")
        with urllib.request.urlopen(req, timeout=5) as response:
            assert response.status == 200
            body = response.read().decode("utf-8")
    except Exception as exc:
        pytest.fail(f"Failed to connect to Nginx/Flask pipeline: {exc}")

    try:
        client = redis.Redis(host="localhost", port=6379, db=0)
        redis_value = client.get("latest_patch")
    except Exception as exc:
        pytest.fail(f"Failed to get latest_patch from Redis: {exc}")

    assert body == expected, f"Unexpected HTTP response: {body!r}"
    assert redis_value is not None, "Redis key latest_patch was not written"
    assert redis_value.decode("utf-8") == expected, (
        f"Redis value {redis_value!r} does not contain the decoder's literal stdout"
    )
    assert body == redis_value.decode("utf-8"), (
        "HTTP response does not match Redis value"
    )
    assert "TARGET=" in body and "RESULT=" in body
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
