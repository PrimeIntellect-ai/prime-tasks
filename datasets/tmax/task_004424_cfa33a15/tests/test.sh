#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import subprocess

import cv2
import pytest

AGENT_SCRIPT = "/home/user/api_parser.py"
SOURCE_DIR = "/home/user/legacy_source"
C_BINARY = os.path.join(SOURCE_DIR, "api_parser_c")


def expected_output(binary_string):
    padded = binary_string + "0" * ((-len(binary_string)) % 8)
    h = 0
    for pos in range(0, len(padded), 8):
        byte = int(padded[pos:pos + 8], 2)
        h = (h * 31 + byte) % 65536

    for candidate in range(1, 65536):
        if (h * candidate) % 65536 == 1:
            return str(candidate)
    return "0"


def run_checked(command, timeout=15):
    return subprocess.run(
        command,
        capture_output=True,
        text=True,
        check=True,
        timeout=timeout,
    ).stdout.strip()


def test_legacy_source_builds_and_is_correct_and_leak_free():
    makefile = os.path.join(SOURCE_DIR, "Makefile")
    parser_source = os.path.join(SOURCE_DIR, "parser.c")
    assert os.path.isfile(makefile), f"{makefile} does not exist."
    assert os.path.isfile(parser_source), f"{parser_source} does not exist."

    for name in ("api_parser_c", "api_parser_d"):
        path = os.path.join(SOURCE_DIR, name)
        if os.path.lexists(path):
            os.remove(path)

    subprocess.run(
        ["make"], cwd=SOURCE_DIR, capture_output=True, text=True,
        check=True, timeout=30
    )
    assert os.path.isfile(C_BINARY), "make did not create api_parser_c"
    assert os.access(C_BINARY, os.X_OK), "api_parser_c is not executable"
    with open(C_BINARY, "rb") as executable:
        assert executable.read(4) == b"\x7fELF", "api_parser_c is not a compiled executable"

    cases = [
        "0", "1", "101", "11111111", "000000001", "1010101000001111",
        "1101001001010111101010001110001101010101110000111010",
    ]
    random.seed(314159)
    for _ in range(40):
        length = random.randint(1, 128)
        cases.append("".join(random.choice("01") for _ in range(length)))

    for binary_string in cases:
        actual = run_checked([C_BINARY, binary_string])
        assert actual == expected_output(binary_string), (
            f"C parser mismatch on input {binary_string}: got {actual}"
        )

    subprocess.run(
        [
            "valgrind", "--quiet", "--leak-check=full",
            "--show-leak-kinds=all", "--errors-for-leak-kinds=all",
            "--error-exitcode=99", C_BINARY, "1010101000001111",
        ],
        capture_output=True,
        text=True,
        check=True,
        timeout=30,
    )


def test_api_parser_fuzz_equivalence():
    assert os.path.isfile(AGENT_SCRIPT), f"{AGENT_SCRIPT} does not exist."

    random.seed(42)
    for _ in range(100):
        length = random.randint(16, 128)
        binary_string = "".join(random.choice("01") for _ in range(length))
        expected = expected_output(binary_string)

        try:
            agent_output = run_checked(
                ["/usr/bin/python3", AGENT_SCRIPT, binary_string]
            )
        except subprocess.CalledProcessError as exc:
            pytest.fail(f"Agent script failed on input {binary_string}: {exc.stderr}")

        assert expected == agent_output, (
            f"Mismatch on input {binary_string}.\n"
            f"Expected output: {expected}\n"
            f"Agent output: {agent_output}"
        )


def test_integration_result():
    result_file = "/home/user/integration_result.txt"
    video_file = "/app/api_test_capture.mp4"
    assert os.path.isfile(result_file), f"{result_file} does not exist."
    assert os.path.isfile(video_file), f"{video_file} does not exist."

    capture = cv2.VideoCapture(video_file)
    assert capture.isOpened(), "Could not open integration video"
    bits = []
    while True:
        ok, frame = capture.read()
        if not ok:
            break
        bits.append("1" if float(frame[0:10, 0:10].mean()) >= 128 else "0")
    capture.release()
    assert bits, "Integration video contained no frames"

    binary_string = "".join(bits)
    expected_result = expected_output(binary_string)
    assert expected_result == "4219"

    with open(result_file, "r") as result:
        content = result.read().strip()
    assert content == "4219", f"Expected integration result '4219', got '{content}'"

    actual_execution = run_checked(
        ["/usr/bin/python3", AGENT_SCRIPT, binary_string]
    )
    assert content == actual_execution, (
        "integration_result.txt does not match api_parser.py run on the video stream"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
