#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import string
import subprocess
import pytest

SOLUTION_DIR = "/home/user/solution"
CRASH_INPUT = os.path.join(SOLUTION_DIR, "crash_input.bin")
FAULT_FUNC = os.path.join(SOLUTION_DIR, "fault_func.txt")
SAFE_PARSER = os.path.join(SOLUTION_DIR, "safe_parser.c")
FIXED_SERVER = os.path.join(SOLUTION_DIR, "fixed_server")
REBUILT_SERVER = "/tmp/rebuilt_server"
PARSER_HARNESS = "/tmp/parser_harness"


def run_program(path, data):
    return subprocess.run(
        [path], input=data, capture_output=True, timeout=5, check=False
    )


def expected_result(data):
    colon = data.find(b":")
    if colon < 0:
        return b"", 0
    field = data[colon + 1:colon + 1 + 31]
    return b"Field: " + field + b"\n", len(field)


def test_crash_input_bin():
    assert os.path.isfile(CRASH_INPUT), f"Missing {CRASH_INPUT}"
    with open(CRASH_INPUT, "rb") as f:
        content = f.read()
    expected = b"USER:" + b"A"*64 + b"\n"
    assert content == expected, f"Content of {CRASH_INPUT} is incorrect. Expected {expected}, got {content}"


def test_fault_func_txt():
    assert os.path.isfile(FAULT_FUNC), f"Missing {FAULT_FUNC}"
    with open(FAULT_FUNC, "r") as f:
        content = f.read().strip()
    assert content == "extract_field", f"Content of {FAULT_FUNC} is incorrect. Expected 'extract_field', got '{content}'"


def test_safe_parser_c():
    assert os.path.isfile(SAFE_PARSER), f"Missing {SAFE_PARSER}"
    with open(SAFE_PARSER, "r") as f:
        content = f.read()
    assert "parse_and_process" in content, f"Function 'parse_and_process' not found in {SAFE_PARSER}"


def test_fixed_server_exists_and_executable():
    assert os.path.isfile(FIXED_SERVER), f"Missing {FIXED_SERVER}"
    assert os.access(FIXED_SERVER, os.X_OK), f"{FIXED_SERVER} is not executable"
    with open(FIXED_SERVER, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{FIXED_SERVER} is not a compiled ELF executable"


def test_fixed_server_behavior():
    with open(CRASH_INPUT, "rb") as f:
        crash_data = f.read()

    proc = run_program(FIXED_SERVER, crash_data)
    assert proc.returncode == 0, f"{FIXED_SERVER} crashed or returned non-zero exit code on crash input"

    valid_input = b"DATA:short_value\n"
    proc_valid = run_program(FIXED_SERVER, valid_input)
    assert proc_valid.returncode == 0, f"{FIXED_SERVER} returned non-zero exit code on valid input"
    assert b"short_value" in proc_valid.stdout, f"{FIXED_SERVER} did not process valid input correctly"


def test_fixed_server_truncation():
    long_input = b"TEST:" + b"B"*50 + b"\n"
    proc = run_program(FIXED_SERVER, long_input)
    assert proc.returncode == 0, f"{FIXED_SERVER} crashed on long input"
    assert b"B"*32 not in proc.stdout, f"{FIXED_SERVER} did not truncate the output to 31 characters"


@pytest.fixture(scope="session")
def compiled_artifacts():
    rebuilt = subprocess.run(
        ["gcc", "-std=c11", "-O2", "/home/user/ticket/main.c", SAFE_PARSER, "-o", REBUILT_SERVER],
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert rebuilt.returncode == 0, "safe_parser.c does not compile with main.c:\n" + rebuilt.stderr

    harness_source = r'''
#include <stdio.h>
#include <unistd.h>
extern int parse_and_process(char *input);
int main(void) {
    char buf[512];
    ssize_t n = read(0, buf, 511);
    if (n <= 0) return 0;
    buf[n] = '\0';
    int result = parse_and_process(buf);
    fprintf(stderr, "RET:%d\n", result);
    return 0;
}
'''
    with open("/tmp/parser_harness.c", "w") as f:
        f.write(harness_source)
    harness = subprocess.run(
        ["gcc", "-std=c11", "-O2", "/tmp/parser_harness.c", SAFE_PARSER, "-o", PARSER_HARNESS],
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert harness.returncode == 0, "safe_parser.c does not expose a usable parse_and_process function:\n" + harness.stderr
    return REBUILT_SERVER, PARSER_HARNESS


def make_cases():
    cases = [
        b"",
        b"NO_DELIMITER_HERE\n",
        b":",
        b"X:a",
        b"DATA:short_value\n",
        b"PING:pong_value\n",
        b"A:first:second:value\n",
        b"USER:" + b"A" * 64 + b"\n",
    ]
    alphabet = string.ascii_letters + string.digits + "_-+=.,/ "
    for length in [0, 1, 2, 29, 30, 31, 32, 33, 50, 100, 200]:
        prefix = "".join(secrets.choice(string.ascii_letters) for _ in range(secrets.randbelow(12) + 1))
        value = "".join(secrets.choice(alphabet) for _ in range(length))
        cases.append((prefix + ":" + value + "\n").encode())
    for _ in range(24):
        prefix = "".join(secrets.choice(string.ascii_letters) for _ in range(secrets.randbelow(20) + 1))
        length = secrets.randbelow(240)
        value = "".join(secrets.choice(alphabet) for _ in range(length))
        cases.append((prefix + ":" + value + ("\n" if secrets.randbelow(2) else "")).encode())
    return cases


def test_compiled_source_and_fixed_server_full_behavior(compiled_artifacts):
    rebuilt_server, parser_harness = compiled_artifacts
    for data in make_cases():
        expected_stdout, expected_return = expected_result(data)

        rebuilt = run_program(rebuilt_server, data)
        assert rebuilt.returncode == 0, f"server rebuilt from safe_parser.c failed for input {data!r}"
        assert rebuilt.stdout == expected_stdout, (
            f"safe_parser.c produced incorrect output for {data!r}: "
            f"expected {expected_stdout!r}, got {rebuilt.stdout!r}"
        )

        submitted = run_program(FIXED_SERVER, data)
        assert submitted.returncode == 0, f"fixed_server failed for input {data!r}"
        assert submitted.stdout == expected_stdout, (
            f"fixed_server produced incorrect output for {data!r}: "
            f"expected {expected_stdout!r}, got {submitted.stdout!r}"
        )

        if data:
            harness = run_program(parser_harness, data)
            assert harness.returncode == 0, f"parse_and_process failed for input {data!r}"
            assert harness.stdout == expected_stdout, f"parse_and_process printed incorrect output for {data!r}"
            assert harness.stderr == f"RET:{expected_return}\n".encode(), (
                f"parse_and_process returned the wrong length for {data!r}: {harness.stderr!r}"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
