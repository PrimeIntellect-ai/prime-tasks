#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import re
import secrets
import stat
import subprocess

import pytest

HOME = "/home/user"
SOURCE = os.path.join(HOME, "tx-processor.go")
BINARY = os.path.join(HOME, "tx-processor")
BATCH = os.path.join(HOME, "batch_data.csv")
FIXED = os.path.join(HOME, "batch_data_fixed.csv")
TRACE = os.path.join(HOME, "strace.log")


def transformed(data):
    return b"".join(
        line.replace(b"USD", b"USD-PROCESSED") + b"\n"
        for line in data.splitlines()
        if line != b""
    )


def run_processor(program, data):
    result = subprocess.run(
        [program], input=data, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        timeout=10, check=False
    )
    assert result.returncode == 0, (
        f"{program} exited with {result.returncode}: "
        f"{result.stderr.decode(errors='replace')}"
    )
    return result.stdout


def test_strace_log_exists_and_valid():
    path = TRACE
    assert os.path.isfile(path), f"File {path} does not exist. You must run strace to trace read and write syscalls."

    with open(path, "r") as f:
        content = f.read()

    assert "read(" in content, f"Expected to find 'read(' syscalls in {path}."
    assert "write(" in content, f"Expected to find 'write(' syscalls in {path}."

    with open(BATCH, "rb") as f:
        batch = f.read()
    expected_buggy_output = b"".join(transformed(batch).splitlines(keepends=True)[:-1])

    write_pattern = re.compile(
        r'write\(1(?:<[^>]*>)?,\s*("(?:\\.|[^"\\])*")(?:\.\.\.)?,\s*(\d+)\)\s*=\s*(\d+)'
    )
    writes = []
    for match in write_pattern.finditer(content):
        requested = int(match.group(2))
        returned = int(match.group(3))
        assert returned == requested, "The recorded stdout trace contains a short or inconsistent write."
        decoded = ast.literal_eval(match.group(1)).encode("utf-8")
        assert len(decoded) == returned, "The recorded stdout write payload does not match its return value."
        writes.append(decoded)

    assert writes, "No parseable write(1, ...) syscall records were found in strace.log."
    assert b"".join(writes) == expected_buggy_output, (
        "strace.log does not record the buggy processor writing exactly the transformed first 99 records."
    )

    read_pattern = re.compile(
        r'read\(0(?:<[^>]*>)?,\s*"(?:\\.|[^"\\])*"(?:\.\.\.)?,\s*\d+\)\s*=\s*(\d+)'
    )
    read_results = [int(m.group(1)) for m in read_pattern.finditer(content)]
    assert read_results, "No parseable read(0, ...) syscall records were found in strace.log."
    assert sum(n for n in read_results if n > 0) == len(batch), (
        "The traced stdin reads do not account for the complete batch_data.csv input."
    )
    assert 0 in read_results, "The trace does not show the processor reading stdin through EOF."


def test_fixed_output_csv():
    path = FIXED
    assert os.path.isfile(path), f"File {path} does not exist. You must generate the fixed output."

    with open(path, "r") as f:
        lines = f.read().splitlines()

    assert len(lines) == 100, f"Expected {path} to have exactly 100 lines, but found {len(lines)}."

    last_line = lines[-1]
    expected_last_line = "TX1099,198.99,USD-PROCESSED"
    assert last_line == expected_last_line, f"Expected last line to be '{expected_last_line}', but got '{last_line}'."

    with open(BATCH, "rb") as f:
        expected = transformed(f.read())
    with open(path, "rb") as f:
        actual = f.read()
    assert actual == expected, "batch_data_fixed.csv is not the complete line-by-line transformation of batch_data.csv."


def test_go_source_fixed_and_artifacts_work(tmp_path):
    path = SOURCE
    assert os.path.isfile(path), f"File {path} does not exist."

    with open(path, "r") as f:
        content = f.read()

    assert "len(records)-1" not in content, f"The off-by-one bug 'len(records)-1' is still present in {path}."

    assert os.path.isfile(BINARY), f"File {BINARY} does not exist."
    mode = os.stat(BINARY).st_mode
    assert mode & stat.S_IXUSR, f"{BINARY} is not executable."
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{BINARY} is not a compiled ELF binary."

    rebuilt = str(tmp_path / "tx-processor-from-source")
    build = subprocess.run(
        ["go", "build", "-o", rebuilt, SOURCE],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=60, check=False
    )
    assert build.returncode == 0, (
        "The repaired Go source does not compile: " + build.stderr.decode(errors="replace")
    )

    token = secrets.token_hex(12).encode()
    cases = [
        b"ONLY-" + token + b",1.00,USD\n",
        (
            b"A-" + token + b",USD,USD\n"
            b"\n"
            b"B-" + token + b",2.00,EUR\n"
            b"C-" + token + b",3.00,USD\n"
            b"D-" + token + b",USDUSD,USD\n"
        ),
    ]
    for data in cases:
        expected = transformed(data)
        assert run_processor(rebuilt, data) == expected, "The repaired source fails a generated transformation case."
        assert run_processor(BINARY, data) == expected, "The installed tx-processor binary is not correctly repaired."

    with open(BATCH, "rb") as f:
        batch = f.read()
    assert run_processor(BINARY, batch) == transformed(batch), (
        "The installed tx-processor does not produce the complete expected batch output."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
