#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import resource
import subprocess
import tempfile
import pytest

SOURCE = "/home/user/extract_ts.c"
EXECUTABLE = "/home/user/extract_ts"
REBUILT = "/tmp/extract_ts_verified"


def test_source_code_exists():
    """Test that the C program source code exists."""
    assert os.path.exists(SOURCE), "The C source code file /home/user/extract_ts.c is missing."
    assert os.path.isfile(SOURCE), "/home/user/extract_ts.c is not a file."


def test_executable_exists():
    """Test that the compiled executable exists."""
    assert os.path.exists(EXECUTABLE), "The compiled executable /home/user/extract_ts is missing."
    assert os.path.isfile(EXECUTABLE), "/home/user/extract_ts is not a file."
    assert os.access(EXECUTABLE, os.X_OK), "/home/user/extract_ts is not executable."
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "/home/user/extract_ts is not a compiled ELF executable."


def test_output_file_exists():
    """Test that the output CSV file exists."""
    assert os.path.exists("/home/user/fr_menu_ts.csv"), "The output file /home/user/fr_menu_ts.csv is missing."
    assert os.path.isfile("/home/user/fr_menu_ts.csv"), "/home/user/fr_menu_ts.csv is not a file."


def test_source_uses_posix_regex():
    """The requested implementation must use the POSIX regex API."""
    with open(SOURCE, "r", encoding="utf-8", errors="replace") as f:
        source = f.read()
    assert re.search(r"#\s*include\s*<regex\.h>", source), "extract_ts.c must include <regex.h>."
    assert re.search(r"\bregcomp\s*\(", source), "extract_ts.c must compile a POSIX regular expression with regcomp()."
    assert re.search(r"\bregexec\s*\(", source), "extract_ts.c must perform POSIX regex matching with regexec()."


def test_source_compiles():
    """Compile the submitted source independently for behavioral testing."""
    result = subprocess.run(
        ["gcc", "-O2", "-std=c11", SOURCE, "-o", REBUILT],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, "extract_ts.c did not compile:\n" + result.stderr
    assert os.path.isfile(REBUILT) and os.access(REBUILT, os.X_OK)


def expected_for(data):
    pattern = re.compile(r"^menu_[a-z]+_[0-9]+$")
    rows = []
    for raw in data.decode("ascii").splitlines():
        parts = raw.split(",")
        if len(parts) != 4:
            continue
        ts_str, loc, key, rt_str = parts
        try:
            ts = int(ts_str)
            rt = int(rt_str)
        except ValueError:
            continue
        if loc != "fr_FR" or pattern.fullmatch(key) is None:
            continue
        rows.append(f"{(ts // 3600) * 3600},{key},{'FAST' if rt < 100 else 'SLOW'}")
    return rows


def run_and_check(program, data):
    result = subprocess.run(
        [program], input=data, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10
    )
    assert result.returncode == 0, f"{program} exited with status {result.returncode}: {result.stderr.decode(errors='replace')}"
    actual = result.stdout.decode("utf-8", errors="strict").splitlines()
    assert actual == expected_for(data), f"Unexpected output from {program}: {actual!r}"


def test_programs_process_unseen_stream_correctly():
    """Execute both the delivered binary and a fresh build on verifier-generated input."""
    assert os.path.exists(REBUILT), "Independent build is missing."
    data = (
        b"1700004500,fr_FR,menu_file_01,45\n"
        b"1700004501,fr_FR,menu_edit_02,99\r\n"
        b"1700004502,fr_FR,menu_view_99,100\n"
        b"1700004503,en_US,menu_file_01,20\n"
        b"1700004504,fr_FR,menu_File_01,20\n"
        b"1700004505,fr_FR,menu_file_abc,20\n"
        b"1700004506,fr_FR,menu_file_01_extra,20\n"
        b"1700004507,fr_FR,button_ok,20\n"
        b"not_a_timestamp,fr_FR,menu_help_00,20\n"
        b"1700004508,fr_FR,menu_help_00,not_a_time\n"
        b"1700004509,fr_FR,menu_help_00,20,extra\n"
        b"malformed,line,here\n"
        b"\n"
        b"0,fr_FR,menu_help_00,10\n"
        b"2147487200,fr_FR,menu_view_99,200\n"
    )
    run_and_check(EXECUTABLE, data)
    run_and_check(REBUILT, data)


def _limit_memory():
    limit = 32 * 1024 * 1024
    resource.setrlimit(resource.RLIMIT_AS, (limit, limit))


def test_programs_stream_large_input_with_bounded_memory():
    """A large input must be processed without retaining the whole stream in memory."""
    path = "/tmp/large_extract_ts_input.csv"
    line = b"malformed,line,here\n"
    block = line * 4096
    target = 48 * 1024 * 1024
    written = 0
    with open(path, "wb") as f:
        while written < target:
            f.write(block)
            written += len(block)

    for program in (EXECUTABLE, REBUILT):
        with open(path, "rb") as stream:
            result = subprocess.run(
                [program],
                stdin=stream,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.PIPE,
                preexec_fn=_limit_memory,
                timeout=20,
            )
        assert result.returncode == 0, f"{program} failed while streaming a large input under a memory limit."


def test_output_contents():
    """Test that the output file contains the correctly processed data."""
    input_file = "/home/user/loc_logs.csv"
    output_file = "/home/user/fr_menu_ts.csv"

    assert os.path.exists(input_file), f"Input file {input_file} is missing."
    assert os.path.exists(output_file), f"Output file {output_file} is missing."

    expected_rows = []
    pattern = re.compile(r"^menu_[a-z]+_[0-9]+$")

    with open(input_file, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split(",")
            if len(parts) != 4:
                continue
            ts_str, loc, key, rt_str = parts
            try:
                ts = int(ts_str)
                rt = int(rt_str)
            except ValueError:
                continue

            if loc != "fr_FR":
                continue

            if not pattern.match(key):
                continue

            ts_hour = (ts // 3600) * 3600
            cat = "FAST" if rt < 100 else "SLOW"
            expected_rows.append(f"{ts_hour},{key},{cat}")

    with open(output_file, "r") as f:
        actual_rows = [line.strip() for line in f if line.strip()]

    assert len(actual_rows) == len(expected_rows), f"Row count mismatch. Expected {len(expected_rows)}, got {len(actual_rows)}."

    for i, (exp, act) in enumerate(zip(expected_rows, actual_rows)):
        assert exp == act, f"Mismatch at line {i+1}: expected '{exp}', got '{act}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
