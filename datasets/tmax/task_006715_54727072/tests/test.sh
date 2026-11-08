#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
import tempfile
import pytest

PROJECT = "/home/user/project"
SOURCE = os.path.join(PROJECT, "data_parser.c")
SCRIPT = os.path.join(PROJECT, "test_all.sh")
FLAG = os.path.join(PROJECT, "pass.flag")
ASAN_BINARY = "/tmp/data_parser_asan"
TRACE_BINARY = "/tmp/data_parser_trace"


def run(cmd, **kwargs):
    return subprocess.run(cmd, text=True, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, timeout=30, **kwargs)


@pytest.fixture(scope="module")
def verified_artifacts():
    assert os.path.isfile(SOURCE), f"Missing source file {SOURCE}."
    assert os.path.isfile(SCRIPT), f"Missing test script {SCRIPT}."
    assert os.access(SCRIPT, os.X_OK), f"Test script {SCRIPT} is not executable."

    # Ensure the required flag is freshly produced by an actual successful run.
    try:
        os.remove(FLAG)
    except FileNotFoundError:
        pass
    result = run([SCRIPT], cwd=PROJECT)
    assert result.returncode == 0, (
        f"test_all.sh failed with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(FLAG), "test_all.sh did not generate pass.flag."

    # The supplied inputs must not have been altered to hide the overflow.
    for i in range(50):
        path = f"/home/user/inputs/input_{i:03d}.dat"
        assert os.path.isfile(path), f"Missing input file {path}."
        with open(path, "rb") as f:
            data = f.read()
        if i == 37:
            assert data == b"A" * 120, f"The malformed input {path} was altered."
        else:
            assert len(data) == 16, f"Unexpected size for input file {path}."

    asan_build = run([
        "gcc", "-std=c11", "-O0", "-g", "-fno-omit-frame-pointer",
        "-fsanitize=address", SOURCE, "-o", ASAN_BINARY
    ])
    assert asan_build.returncode == 0, (
        f"data_parser.c does not compile with AddressSanitizer.\n"
        f"stdout:\n{asan_build.stdout}\nstderr:\n{asan_build.stderr}"
    )

    trace_build = run([
        "gcc", "-std=c11", "-O0", SOURCE, "-o", TRACE_BINARY
    ])
    assert trace_build.returncode == 0, (
        f"data_parser.c does not compile.\n"
        f"stdout:\n{trace_build.stdout}\nstderr:\n{trace_build.stderr}"
    )

    symbols = run(["nm", TRACE_BINARY])
    assert symbols.returncode == 0
    assert re.search(r"\bparse_record$", symbols.stdout, re.MULTILINE), (
        "The compiled program does not contain the required parse_record function."
    )
    return ASAN_BINARY, TRACE_BINARY


def test_pass_flag_exists(verified_artifacts):
    flag_path = "/home/user/project/pass.flag"
    assert os.path.isfile(flag_path), f"Expected flag file {flag_path} does not exist. The test_all.sh script may not have completed successfully."


def test_fixed_program_is_safe_and_processes_inputs(verified_artifacts):
    asan_binary, trace_binary = verified_artifacts
    env = os.environ.copy()
    env["ASAN_OPTIONS"] = "abort_on_error=1:detect_leaks=0"

    # Exercise every supplied input under ASan, including the original trigger.
    for i in range(50):
        path = f"/home/user/inputs/input_{i:03d}.dat"
        result = run([asan_binary, path], env=env)
        assert result.returncode == 0, (
            f"Sanitizer failure while processing {path}.\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )

    # Also test a larger derived input so the read must respect buffer capacity.
    with tempfile.TemporaryDirectory() as td:
        large_path = os.path.join(td, "large.dat")
        x_path = os.path.join(td, "marked.dat")
        normal_path = os.path.join(td, "normal.dat")
        with open(large_path, "wb") as f:
            f.write(b"A" * 4096)
        with open(x_path, "wb") as f:
            f.write(b"X" + b"B" * 255)
        with open(normal_path, "wb") as f:
            f.write(b"N" * 256)

        for path in (large_path, x_path, normal_path):
            result = run([asan_binary, path], env=env)
            assert result.returncode == 0, (
                f"Sanitizer failure on generated input {path}.\n{result.stderr}"
            )

        marked = run([trace_binary, x_path])
        assert marked.returncode == 0
        assert marked.stdout == "Record marked X\n", (
            "The repaired parser no longer processes X-marked records correctly."
        )
        normal = run([trace_binary, normal_path])
        assert normal.returncode == 0
        assert normal.stdout == "", "An unmarked record produced unexpected output."


def test_resolution_txt(verified_artifacts):
    _, trace_binary = verified_artifacts
    res_path = "/home/user/resolution.txt"
    assert os.path.isfile(res_path), f"Expected report file {res_path} does not exist."

    with open(res_path, "r") as f:
        raw_lines = f.read().splitlines()
    assert len(raw_lines) == 3, f"Expected exactly 3 lines in {res_path}, found {len(raw_lines)}."
    assert all(line.strip() for line in raw_lines), f"Blank lines are not allowed in {res_path}."
    lines = [line.strip() for line in raw_lines if line.strip() != ""]

    assert len(lines) >= 3, f"Expected at least 3 lines in {res_path}, found {len(lines)}."
    file_crash = lines[0]
    syscall = lines[1]
    func_name = lines[2]

    assert file_crash == "/home/user/inputs/input_037.dat", f"Line 1: Expected '/home/user/inputs/input_037.dat', got '{file_crash}'."
    assert syscall in ("openat", "open"), f"Line 2: Expected 'openat' or 'open', got '{syscall}'."
    assert func_name == "parse_record", f"Line 3: Expected 'parse_record', got '{func_name}'."

    trace_path = "/tmp/data_parser.strace"
    traced = run([
        "strace", "-qq", "-e", "trace=open,openat", "-o", trace_path,
        trace_binary, file_crash
    ])
    assert traced.returncode == 0, f"The repaired parser failed under strace: {traced.stderr}"
    with open(trace_path, "r") as f:
        trace = f.read()

    escaped_path = re.escape(file_crash)
    matches = re.findall(
        r"^\s*(?:\[pid\s+\d+\]\s+)?(openat|open)\([^\n]*\"" + escaped_path + r"\"",
        trace,
        re.MULTILINE,
    )
    assert matches, f"The parser did not open {file_crash} in the system-call trace."
    actual_syscall = matches[-1]
    assert syscall == actual_syscall, (
        f"Line 2 reports '{syscall}', but the trace used '{actual_syscall}' to open {file_crash}."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
