#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import tempfile
import pytest

CRASH_INPUT = "/home/user/crash_input.txt"
MRE_SOURCE = "/home/user/mre.go"
DIAGNOSTIC = "/home/user/diagnostic.log"
EXPECTED_PAYLOAD = '{"op": "multiply", "args": [18446744073709551616, 55'
SUBMISSION_BIN = "/tmp/mre_submission"
REFERENCE_BIN = "/tmp/mre_reference"


def test_crash_input_content():
    """Verify that crash_input.txt contains the exact extracted payload."""
    assert os.path.exists(CRASH_INPUT), f"File {CRASH_INPUT} does not exist."
    with open(CRASH_INPUT, "r", encoding="utf-8") as f:
        content = f.read()

    assert content == EXPECTED_PAYLOAD, (
        f"Content of {CRASH_INPUT} is incorrect. Expected "
        f"'{EXPECTED_PAYLOAD}', got '{content}'."
    )


def test_mre_go_exists_and_looks_valid():
    """Preserve the original source checks and ensure the program compiles."""
    assert os.path.exists(MRE_SOURCE), f"Go program {MRE_SOURCE} does not exist."
    assert os.path.isfile(MRE_SOURCE), f"Go program {MRE_SOURCE} is not a regular file."
    with open(MRE_SOURCE, "r", encoding="utf-8") as f:
        content = f.read()

    assert "package main" in content, "mre.go does not contain 'package main'."
    assert "MathRequest" in content, "mre.go does not define the MathRequest struct."
    assert "json.Unmarshal" in content or "json.NewDecoder" in content, (
        "mre.go does not seem to use json unmarshaling."
    )
    assert "crash_input.txt" in content, "mre.go does not reference the crash_input.txt file."

    result = subprocess.run(
        ["go", "build", "-o", SUBMISSION_BIN, MRE_SOURCE],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        "mre.go does not compile:\n" + result.stderr.decode("utf-8", errors="replace")
    )
    assert os.path.isfile(SUBMISSION_BIN) and os.access(SUBMISSION_BIN, os.X_OK)


def build_reference():
    source = r'''package main

import (
    "encoding/json"
    "fmt"
    "os"
)

type MathRequest struct {
    Operation string   `json:"op"`
    Arguments []uint64 `json:"args"`
}

func main() {
    data, err := os.ReadFile("/home/user/crash_input.txt")
    if err != nil {
        fmt.Println(err)
        return
    }
    var request MathRequest
    if err := json.Unmarshal(data, &request); err != nil {
        fmt.Println(err)
    }
}
'''
    path = "/tmp/mre_reference.go"
    with open(path, "w", encoding="utf-8") as f:
        f.write(source)
    result = subprocess.run(
        ["go", "build", "-o", REFERENCE_BIN, path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, result.stderr.decode("utf-8", errors="replace")


def run_binary(binary):
    return subprocess.run(
        [binary],
        cwd="/tmp",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )


def normalized_stdout(result):
    return result.stdout.decode("utf-8", errors="strict").rstrip("\r\n")


def test_mre_executes_with_required_behavior():
    """Execute the compiled MRE against several inputs and compare with Go's JSON behavior."""
    assert os.path.exists(SUBMISSION_BIN), "Compiled MRE is missing."
    build_reference()

    with open(CRASH_INPUT, "rb") as f:
        original = f.read()

    cases = [
        original,
        b'{"op":"multiply","args":[2,55]}',
        b'{"op":"multiply","args":[18446744073709551616,55]}',
        b'{"op":17,"args":[1,2]}',
        b'{"op":"add","args":[1,-7]}',
    ]

    try:
        for payload in cases:
            with open(CRASH_INPUT, "wb") as f:
                f.write(payload)

            expected = run_binary(REFERENCE_BIN)
            actual = run_binary(SUBMISSION_BIN)

            assert expected.returncode == 0
            assert actual.returncode == 0, (
                "mre.go exited unsuccessfully: "
                + actual.stderr.decode("utf-8", errors="replace")
            )
            assert actual.stderr == b"", (
                "mre.go must print only the unmarshal error to standard output; "
                "it wrote to stderr."
            )
            assert normalized_stdout(actual) == normalized_stdout(expected), (
                "mre.go output did not match encoding/json for input "
                f"{payload!r}. Expected {normalized_stdout(expected)!r}, "
                f"got {normalized_stdout(actual)!r}."
            )
    finally:
        with open(CRASH_INPUT, "wb") as f:
            f.write(original)


def test_diagnostic_log_content():
    """Preserve the original log check and verify it is actual MRE output."""
    assert os.path.exists(DIAGNOSTIC), f"Log file {DIAGNOSTIC} does not exist."
    with open(DIAGNOSTIC, "r", encoding="utf-8") as f:
        content = f.read().strip()

    assert content, f"{DIAGNOSTIC} is empty."

    valid_errors = [
        "unexpected end of JSON input",
        "json: cannot unmarshal number",
        "unexpected EOF",
    ]
    assert any(err in content for err in valid_errors), (
        "diagnostic.log does not contain a recognized JSON unmarshal error. "
        f"Content was: '{content}'"
    )

    result = run_binary(SUBMISSION_BIN)
    assert result.returncode == 0, (
        "mre.go exited unsuccessfully: "
        + result.stderr.decode("utf-8", errors="replace")
    )
    assert result.stderr == b"", "mre.go wrote unexpected output to stderr."
    assert content == normalized_stdout(result), (
        "diagnostic.log is not the output produced by running mre.go on crash_input.txt."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
