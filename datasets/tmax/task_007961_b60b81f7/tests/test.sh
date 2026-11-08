#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import string
import subprocess

PARSER_DIR = "/home/user/forensics"
SOURCE_PATH = os.path.join(PARSER_DIR, "parser.c")
EXECUTABLE_PATH = os.path.join(PARSER_DIR, "parser")
AUTH_LOG = os.path.join(PARSER_DIR, "auth.log")
OUTPUT_PATH = os.path.join(PARSER_DIR, "parsed_ips.txt")


def run_parser(executable, log_path, cwd):
    output_path = os.path.join(cwd, "parsed_ips.txt")
    if os.path.exists(output_path):
        os.unlink(output_path)

    result = subprocess.run(
        [executable, log_path],
        cwd=cwd,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"Parser exited with status {result.returncode}. "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    assert os.path.isfile(output_path), "Parser did not create parsed_ips.txt."
    with open(output_path, "r") as f:
        return f.read().splitlines()


def make_generated_log(path):
    rng = random.SystemRandom()
    alphabet = string.digits + "."
    lengths = [7, 14, 15, 16, 17, 23, 48]
    tokens = [
        "1.2.3.4",
        "255.255.255.255",
        "192.168.111.2222",
    ]
    tokens.extend("".join(rng.choice(alphabet) for _ in range(n)) for n in lengths)

    expected = []
    with open(path, "w") as f:
        f.write("record without a source address\n")
        for index, token in enumerate(tokens):
            expected.append(token[:15])
            if index % 2:
                f.write(f"event={index} SRC={token}\n")
            else:
                f.write(f"event={index} SRC={token} DST=10.0.0.1\n")
    return expected


def test_parser_executable_exists():
    assert os.path.isfile(EXECUTABLE_PATH), (
        f"Compiled executable {EXECUTABLE_PATH} is missing. Did you compile parser.c?"
    )
    assert os.access(EXECUTABLE_PATH, os.X_OK), f"{EXECUTABLE_PATH} is not executable."
    with open(EXECUTABLE_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{EXECUTABLE_PATH} is not a compiled ELF executable."


def test_parser_c_fixed():
    assert os.path.isfile(SOURCE_PATH), f"Source file {SOURCE_PATH} is missing."
    with open(SOURCE_PATH, "r") as f:
        content = f.read()

    # Ignore explanatory comments while retaining the original assertion against
    # the buggy expression in executable source code.
    code_without_comments = re.sub(r"/\*.*?\*/|//[^\n]*", "", content, flags=re.S)
    assert "i <= 15" not in code_without_comments, (
        "The original off-by-one bug (i <= 15) is still present in parser.c."
    )


def test_submitted_binary_and_source_on_generated_inputs(tmp_path):
    generated_log = tmp_path / "generated.log"
    expected = make_generated_log(generated_log)

    actual = run_parser(EXECUTABLE_PATH, str(generated_log), str(tmp_path))
    assert actual == expected, (
        "The submitted executable did not safely truncate generated source fields "
        "to 15 characters."
    )

    rebuilt = tmp_path / "parser_rebuilt"
    compile_result = subprocess.run(
        ["gcc", SOURCE_PATH, "-o", str(rebuilt)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert compile_result.returncode == 0, (
        f"parser.c does not compile with gcc: {compile_result.stderr}"
    )
    rebuilt_actual = run_parser(str(rebuilt), str(generated_log), str(tmp_path))
    assert rebuilt_actual == expected, (
        "A fresh build of parser.c did not safely truncate generated source fields "
        "to 15 characters."
    )


def test_parsed_ips_exists_and_correct():
    expected_ips = [
        "192.168.1.100",
        "10.5.5.5",
        "255.255.255.255",
        "192.168.111.222",
        "172.16.0.1",
    ]

    run_parser(EXECUTABLE_PATH, AUTH_LOG, PARSER_DIR)
    assert os.path.isfile(OUTPUT_PATH), (
        f"Output file {OUTPUT_PATH} is missing. Did you run the compiled parser?"
    )
    with open(OUTPUT_PATH, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) == len(expected_ips), (
        f"Expected {len(expected_ips)} IPs, but found {len(lines)} in {OUTPUT_PATH}."
    )
    for i, (actual, expected) in enumerate(zip(lines, expected_ips)):
        assert actual == expected, (
            f"Line {i + 1} mismatch: expected '{expected}', got '{actual}'. "
            "The malformed IP might not be truncated correctly."
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
