#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import stat
import struct
import subprocess

import pytest

SOURCE = "/home/user/recover.cpp"
BINARY = "/home/user/recover"
BINLOG = "/home/user/config.binlog"
OUTPUT = "/home/user/recovered_configs.json"

ORIGINAL_PAYLOADS = [
    "server_port=8080\nmax_connections=100",
    "server_port=8081\nmax_connections=200\nenable_cache=true",
    "server_port=8081\nmax_connections=250\nenable_cache=true\nlog_level=debug",
]


def write_log(payloads, trailer=b""):
    with open(BINLOG, "wb") as f:
        for i, payload in enumerate(payloads):
            encoded = payload.encode("utf-8")
            f.write(struct.pack("<4sII", b"CFG1", 1670000000 + i, len(encoded)))
            f.write(encoded)
        f.write(trailer)


def run_recovery():
    if os.path.lexists(OUTPUT):
        os.unlink(OUTPUT)
    result = subprocess.run(
        [BINARY], cwd="/home/user", capture_output=True, text=True, timeout=10
    )
    assert result.returncode == 0, (
        f"Recovery program exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.exists(OUTPUT), f"Expected file {OUTPUT} does not exist after running the program."
    assert os.path.isfile(OUTPUT), f"Expected {OUTPUT} to be a file."
    with open(OUTPUT, "r", encoding="utf-8") as f:
        return json.load(f)


@pytest.fixture(scope="module", autouse=True)
def compile_and_run_original_log():
    assert os.path.exists(SOURCE), f"Expected C++ source {SOURCE} does not exist."
    assert os.path.isfile(SOURCE), f"Expected {SOURCE} to be a file."
    assert stat.S_ISREG(os.stat(SOURCE).st_mode), f"Expected {SOURCE} to be a regular file."

    if os.path.lexists(BINARY):
        os.unlink(BINARY)
    compile_result = subprocess.run(
        ["g++", "-std=c++17", SOURCE, "-o", BINARY],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert compile_result.returncode == 0, (
        f"Failed to compile {SOURCE}.\nstdout:\n{compile_result.stdout}\n"
        f"stderr:\n{compile_result.stderr}"
    )
    assert os.path.isfile(BINARY), f"Compilation did not create {BINARY}."

    truncated_payload = b"server_p"
    trailer = struct.pack("<4sII", b"CFG1", 1670000010, 500) + truncated_payload
    write_log(ORIGINAL_PAYLOADS, trailer)
    run_recovery()
    yield


def test_recovered_configs_json_exists():
    """Check if the recovered_configs.json file was created."""
    filepath = "/home/user/recovered_configs.json"
    assert os.path.exists(filepath), f"Expected file {filepath} does not exist. Did you run your C++ program?"
    assert os.path.isfile(filepath), f"Expected {filepath} to be a file."


def test_recovered_configs_json_content():
    """Check if the recovered_configs.json contains the correct parsed payloads."""
    filepath = "/home/user/recovered_configs.json"

    assert os.path.exists(filepath), f"File {filepath} is missing."

    try:
        with open(filepath, "r", encoding="utf-8") as f:
            data = json.load(f)
    except json.JSONDecodeError as e:
        pytest.fail(f"Failed to parse {filepath} as JSON: {e}")

    expected = ORIGINAL_PAYLOADS

    assert isinstance(data, list), f"Expected JSON root to be a list, but got {type(data).__name__}"
    assert len(data) == len(expected), f"Expected {len(expected)} records, but got {len(data)}. Ensure truncated records are discarded."

    for i, (actual_record, expected_record) in enumerate(zip(data, expected)):
        assert actual_record == expected_record, f"Record at index {i} does not match expected payload.\nExpected:\n{expected_record}\n\nActual:\n{actual_record}"


def test_program_parses_changed_log_and_discards_short_payload():
    token = secrets.token_hex(12)
    expected = [
        f"name={token}\nmode=dynamic",
        f"quoted=\"{token}\"\\path\nempty_value=",
        "final complete record\nwith multiple\nlines",
    ]
    partial = b"incomplete-data"
    trailer = struct.pack("<4sII", b"CFG1", 1900000000, len(partial) + 100) + partial
    write_log(expected, trailer)

    data = run_recovery()
    assert isinstance(data, list), f"Expected JSON root to be a list, but got {type(data).__name__}"
    assert data == expected, "Program did not parse the changed binary log or discard its truncated payload."


def test_program_discards_incomplete_final_header():
    token = secrets.token_hex(10)
    expected = [f"alpha={token}\nbeta=2", "line one\nline two with \"quotes\" and \\slashes"]
    write_log(expected, b"CFG1\x01\x02\x03")

    data = run_recovery()
    assert isinstance(data, list), f"Expected JSON root to be a list, but got {type(data).__name__}"
    assert data == expected, "Program did not gracefully discard an incomplete final header."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
