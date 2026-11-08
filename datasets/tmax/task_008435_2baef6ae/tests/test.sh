#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import tempfile

import pytest

OUTPUT_PATH = "/home/user/fixed_output.txt"
PARSER_PATH = "/home/user/log_tool/parser"
SOURCE_PATH = "/home/user/log_tool/parser.c"
LOG_DIR = "/home/user/logs"

EXPECTED_LINES = [
    "File: /home/user/logs/01.log, Type: INFO, Msg: System started successfully",
    "File: /home/user/logs/01.log, Type: WARN, Msg: CPU temperature high",
    "File: /home/user/logs/02.log, Type: ERROR, Msg: Disk full on /dev/sda1",
    "File: /home/user/logs/02.log, Type: INFO, Msg: Recovery initiated",
    "File: /home/user/logs/02.log, Type: REBOOT, Msg: (none)",
    "File: /home/user/logs/03.log, Type: FATAL, Msg: Kernel panic",
]


def run_parser(executable, directory):
    result = subprocess.run(
        [executable, directory],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
        check=False,
    )
    assert result.returncode == 0, (
        f"{executable} failed with exit code {result.returncode}.\n"
        f"stderr:\n{result.stderr.decode('utf-8', errors='replace')}"
    )
    return result.stdout


def nonempty_lines(data):
    return [line.strip() for line in data.decode("utf-8").splitlines() if line.strip()]


def derive_expected(directory, files):
    expected = []
    for filename, content in files.items():
        if not filename.endswith(".log"):
            continue
        filepath = os.path.join(directory, filename)
        for line in content.splitlines():
            if not line.startswith("EVENT:"):
                continue
            data = line[6:]
            event_type, separator, message = data.partition(" ")
            if not separator:
                message = "(none)"
            expected.append(f"File: {filepath}, Type: {event_type}, Msg: {message}")
    return sorted(expected)


def test_fixed_output_exists():
    assert os.path.isfile(OUTPUT_PATH), f"{OUTPUT_PATH} is missing. Did you save the output?"


def test_fixed_output_content():
    assert os.path.isfile(OUTPUT_PATH), f"{OUTPUT_PATH} is missing"
    with open(OUTPUT_PATH, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert sorted(lines) == sorted(EXPECTED_LINES), (
        f"The content of {OUTPUT_PATH} does not match the expected output.\n"
        f"Expected (sorted):\n{chr(10).join(sorted(EXPECTED_LINES))}\n\n"
        f"Got (sorted):\n{chr(10).join(sorted(lines))}"
    )


def test_parser_compiled():
    assert os.path.isfile(PARSER_PATH), f"The compiled executable {PARSER_PATH} is missing. Did you run make?"
    assert os.access(PARSER_PATH, os.X_OK), f"{PARSER_PATH} is not executable."
    with open(PARSER_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{PARSER_PATH} is not a compiled ELF executable."


def test_saved_output_is_from_successful_parser_run():
    actual_stdout = run_parser(PARSER_PATH, LOG_DIR)
    with open(OUTPUT_PATH, "rb") as f:
        saved_stdout = f.read()
    assert actual_stdout == saved_stdout, (
        f"{OUTPUT_PATH} is not exactly the standard output currently produced by the parser."
    )
    assert sorted(nonempty_lines(actual_stdout)) == sorted(EXPECTED_LINES)


def test_binary_and_source_handle_unseen_missing_message_case():
    assert os.path.isfile(SOURCE_PATH), f"The source file {SOURCE_PATH} is missing."

    token = secrets.token_hex(8)
    type_one = "TYPE_" + secrets.token_hex(5)
    type_two = "EDGE_" + secrets.token_hex(5)
    type_three = "OTHER_" + secrets.token_hex(5)
    message_one = "payload " + secrets.token_hex(10)
    message_three = "details " + secrets.token_hex(10)

    with tempfile.TemporaryDirectory(prefix=f"parser-test-{token}-") as directory:
        files = {
            f"first-{token}.log": (
                "ordinary line to ignore\n"
                f"EVENT:{type_one} {message_one}\n"
                f"EVENT:{type_two}\n"
            ),
            f"second-{token}.log": f"EVENT:{type_three} {message_three}\n",
            f"ignored-{token}.txt": f"EVENT:IGNORED should not appear\n",
        }
        for filename, content in files.items():
            with open(os.path.join(directory, filename), "w") as f:
                f.write(content)

        expected = derive_expected(directory, files)

        submitted_output = run_parser(PARSER_PATH, directory)
        assert sorted(nonempty_lines(submitted_output)) == expected, (
            "The submitted parser did not correctly process unseen log input, "
            "including an EVENT line with no space or message payload."
        )

        rebuilt_parser = os.path.join(directory, "parser-rebuilt")
        compile_result = subprocess.run(
            ["gcc", "-g", "-O0", "-Wall", SOURCE_PATH, "-o", rebuilt_parser],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=15,
            check=False,
        )
        assert compile_result.returncode == 0, (
            "parser.c could not be compiled.\n"
            + compile_result.stderr.decode("utf-8", errors="replace")
        )
        rebuilt_output = run_parser(rebuilt_parser, directory)
        assert sorted(nonempty_lines(rebuilt_output)) == expected, (
            "A fresh executable built from parser.c does not contain the required fix."
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
