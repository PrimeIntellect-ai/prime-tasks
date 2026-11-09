#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import subprocess
import tempfile
import pytest

SOURCE_PATH = "/home/user/stratified_dedup.cpp"
EXEC_PATH = "/home/user/stratified_dedup"
RESULTS_PATH = "/home/user/investigation_results.txt"
INPUT_PATH = "/home/user/input_logs.txt"


def test_cpp_source_exists():
    assert os.path.isfile(SOURCE_PATH), f"The C++ source file {SOURCE_PATH} does not exist."


def test_executable_exists():
    assert os.path.isfile(EXEC_PATH), f"The compiled executable {EXEC_PATH} does not exist."
    assert os.access(EXEC_PATH, os.X_OK), f"The file {EXEC_PATH} is not executable."
    with open(EXEC_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"The file {EXEC_PATH} is not a compiled ELF executable."


def test_investigation_results():
    assert os.path.isfile(RESULTS_PATH), f"The results file {RESULTS_PATH} does not exist."

    expected_output = (
        "[2023-10-01T10:00:06] 192.168.1.6 404 MissingImage\n"
        "[2023-10-01T10:00:00] 192.168.1.1 404 PageNotFound\n"
        "[2023-10-01T10:00:03] 172.16.0.1 500 DatabaseTimeout\n"
        "[2023-10-01T10:00:01] 10.0.0.2 500 InternalServerError\n"
        "[2023-10-01T10:00:10] 192.168.1.10 503 GatewayTimeout\n"
        "[2023-10-01T10:00:05] 192.168.1.5 503 ServiceUnavailable\n"
    )

    with open(RESULTS_PATH, "r") as f:
        actual_content = f.read()

    actual_lines = [line.strip() for line in actual_content.strip().splitlines()]
    expected_lines = [line.strip() for line in expected_output.strip().splitlines()]

    assert actual_lines == expected_lines, (
        f"The content of {RESULTS_PATH} does not match the expected stratified and sorted results.\n"
        f"Expected:\n{chr(10).join(expected_lines)}\n"
        f"Got:\n{chr(10).join(actual_lines)}"
    )


def oracle(input_text):
    output = []
    messages_by_code = {}
    for line in input_text.splitlines():
        parts = line.split(maxsplit=3)
        if len(parts) != 4:
            continue
        code_text = parts[2]
        if re.fullmatch(r"[0-9]+", code_text) is None:
            continue
        code = int(code_text)
        if code < 400 or code > 599:
            continue
        message = parts[3]
        seen = messages_by_code.setdefault(code, set())
        if len(seen) >= 2 or message in seen:
            continue
        seen.add(message)
        output.append(line)
    return output


def run_processor(path, input_text):
    completed = subprocess.run(
        [path], input=input_text, text=True, capture_output=True, timeout=5
    )
    assert completed.returncode == 0, (
        f"{path} exited with status {completed.returncode}. stderr:\n{completed.stderr}"
    )
    return completed.stdout.splitlines()


@pytest.fixture(scope="session")
def rebuilt_executable():
    build_dir = tempfile.mkdtemp(prefix="stratified_build_")
    output = os.path.join(build_dir, "stratified_dedup")
    completed = subprocess.run(
        ["g++", "-std=c++17", "-O2", SOURCE_PATH, "-o", output],
        text=True, capture_output=True, timeout=30
    )
    assert completed.returncode == 0, (
        f"The submitted C++ source does not compile.\n{completed.stdout}\n{completed.stderr}"
    )
    return output


def behavioral_inputs():
    edge_case = "\n".join([
        "[T00] 10.1.0.1 399 TooLow",
        "[T01] 10.1.0.2 400 Alpha",
        "[T02] 10.1.0.3 400 Alpha",
        "[T03] 10.1.0.4 400 Beta",
        "[T04] 10.1.0.5 400 Gamma",
        "[T05] 10.1.0.6 599 UpperOne",
        "[T06] 10.1.0.7 600 TooHigh",
        "[T07] 10.1.0.8 abc NotNumeric",
        "[T08] 10.1.0.9 500x NotNumericEither",
        "[T09] 10.1.0.10 599 UpperTwo",
        "[T10] 10.1.0.11 599 UpperThree",
        "[T11] 10.1.0.12 401 Alpha",
    ]) + "\n"

    rng = random.Random(918273)
    lines = []
    n = 0
    for code in (401, 418, 451, 507, 598):
        for message in ("MsgDelta", "MsgAlpha", "MsgOmega", "MsgBeta"):
            lines.append(f"[R{n:03d}] 172.20.{code % 50}.{n % 250 + 1} {code} {message}")
            n += 1
        lines.append(f"[R{n:03d}] 192.0.2.{n % 250 + 1} {code} MsgAlpha")
        n += 1
    lines.extend([
        f"[R{n:03d}] 198.51.100.1 200 IgnoreSuccess",
        f"[R{n+1:03d}] 198.51.100.2 700 IgnoreLarge",
        f"[R{n+2:03d}] 198.51.100.3 invalid IgnoreText",
    ])
    rng.shuffle(lines)
    randomized = "\n".join(lines) + "\n"
    return [edge_case, randomized]


def test_submitted_executable_behavior():
    for input_text in behavioral_inputs():
        assert run_processor(EXEC_PATH, input_text) == oracle(input_text)


def test_submitted_source_behavior(rebuilt_executable):
    for input_text in behavioral_inputs():
        assert run_processor(rebuilt_executable, input_text) == oracle(input_text)


def test_results_correspond_to_processor_output():
    with open(INPUT_PATH, "r") as f:
        input_text = f.read()
    produced = run_processor(EXEC_PATH, input_text)
    expected_unsorted = oracle(input_text)
    assert produced == expected_unsorted

    def sort_key(line):
        parts = line.split(maxsplit=3)
        return (int(parts[2]), parts[3])

    expected_sorted = sorted(expected_unsorted, key=sort_key)
    with open(RESULTS_PATH, "r") as f:
        saved = [line.strip() for line in f.read().strip().splitlines()]
    assert saved == expected_sorted
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
