#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import json
import os
import secrets
import subprocess

import pytest

HOME = "/home/user"
INPUT = os.path.join(HOME, "requests.json")
OUTPUT = os.path.join(HOME, "output.jsonl")
EXECUTABLE = os.path.join(HOME, "api_tester")


def expected_results(requests):
    results = []
    user_history = {}

    for req in requests:
        req_id = req["req_id"]
        user_id = req["user_id"]
        ts = req["timestamp"]
        history = user_history.setdefault(user_id, [])
        history[:] = [t for t in history if t >= ts - 10]

        if len(history) < 2:
            history.append(ts)
            decoded = base64.b64decode(req["payload"], validate=True)
            results.append({
                "req_id": req_id,
                "status": "ACCEPTED",
                "processed_payload": bytes(b ^ 0x42 for b in decoded).hex(),
            })
        else:
            results.append({
                "req_id": req_id,
                "status": "RATE_LIMITED",
            })

    return results


def read_output():
    assert os.path.isfile(OUTPUT), f"Output file missing: {OUTPUT}"
    actual = []
    with open(OUTPUT, "r", encoding="utf-8") as f:
        for line_num, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            try:
                actual.append(json.loads(line))
            except json.JSONDecodeError:
                pytest.fail(f"Invalid JSON on line {line_num} of {OUTPUT}: {line}")
    return actual


def assert_output_matches(requests):
    expected = expected_results(requests)
    actual = read_output()
    assert len(actual) == len(expected), (
        f"Expected {len(expected)} output lines, got {len(actual)}"
    )
    for i, (got, want) in enumerate(zip(actual, expected), 1):
        assert got == want, (
            f"Mismatch at output line {i}.\nExpected: {want}\nActual: {got}"
        )


def run_program():
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    subprocess.run([EXECUTABLE], cwd=HOME, check=True, timeout=15)
    assert os.path.isfile(OUTPUT), "Program did not create /home/user/output.jsonl"


@pytest.fixture(scope="session", autouse=True)
def build_and_run_original():
    assert os.path.isfile(os.path.join(HOME, "api_tester.cpp")), "Missing /home/user/api_tester.cpp"
    assert os.path.isfile(os.path.join(HOME, "Makefile")), "Missing /home/user/Makefile"
    assert os.path.isfile(INPUT), f"Input file missing: {INPUT}"

    if os.path.exists(EXECUTABLE):
        os.remove(EXECUTABLE)
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)

    subprocess.run(["make", "-B"], cwd=HOME, check=True, timeout=30)
    assert os.path.isfile(EXECUTABLE), "Missing executable /home/user/api_tester after make"
    assert os.access(EXECUTABLE, os.X_OK), "/home/user/api_tester is not executable"
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "/home/user/api_tester is not a compiled ELF executable"

    run_program()


def test_source_and_makefile_exist():
    assert os.path.isfile("/home/user/api_tester.cpp"), "Missing /home/user/api_tester.cpp"
    assert os.path.isfile("/home/user/Makefile"), "Missing /home/user/Makefile"


def test_executable_exists():
    assert os.path.isfile("/home/user/api_tester"), "Missing executable /home/user/api_tester"
    assert os.access("/home/user/api_tester", os.X_OK), "/home/user/api_tester is not executable"


def test_output_jsonl_correctness():
    with open(INPUT, "r", encoding="utf-8") as f:
        requests = json.load(f)
    assert_output_matches(requests)


def test_program_on_runtime_generated_requests():
    with open(INPUT, "rb") as f:
        original_input = f.read()

    rng = secrets.SystemRandom()
    nonce = secrets.token_hex(8)
    base_ts = rng.randrange(20000, 200000)
    user_a = "user-A-" + nonce
    user_b = "user-B-" + nonce
    schedule = [
        (0, user_a),
        (1, user_b),
        (3, user_a),
        (4, user_a),
        (10, user_a),
        (11, user_a),
        (12, user_b),
        (13, user_b),
        (14, user_b),
        (22, user_a),
    ]

    requests = []
    for i, (offset, user_id) in enumerate(schedule):
        payload = secrets.token_bytes(rng.randrange(1, 25))
        requests.append({
            "req_id": f"dynamic-{nonce}-{i}",
            "user_id": user_id,
            "timestamp": base_ts + offset,
            "payload": base64.b64encode(payload).decode("ascii"),
        })

    try:
        with open(INPUT, "w", encoding="utf-8") as f:
            json.dump(requests, f)
        run_program()
        assert_output_matches(requests)
    finally:
        with open(INPUT, "wb") as f:
            f.write(original_input)
        run_program()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
