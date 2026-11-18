#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import os
import secrets
import sqlite3
import struct
import subprocess
import tempfile
import pytest

HOME = "/home/user"


def exercise_parser_library(lib_path):
    lib = ctypes.CDLL(lib_path)
    parse_record = lib.parse_record
    parse_record.argtypes = [
        ctypes.POINTER(ctypes.c_ubyte),
        ctypes.c_int,
        ctypes.POINTER(ctypes.c_char),
    ]
    parse_record.restype = None

    payload = bytes((ord('A') + (i % 26)) for i in range(300))
    data = (ctypes.c_ubyte * len(payload)).from_buffer_copy(payload)
    region = (ctypes.c_ubyte * 1024)(*([0xA5] * 1024))
    out = ctypes.cast(ctypes.byref(region, 128), ctypes.POINTER(ctypes.c_char))
    parse_record(data, len(payload), out)

    actual = bytes(region)
    assert actual[128:383] == payload[:255], "Parser did not preserve the first 255 bytes."
    assert actual[383] == 0, "Parser did not null-terminate at out_buf[255]."
    assert actual[384:478] == bytes([0xA5]) * 94, "Parser wrote beyond the 256-byte output buffer."


def test_parser_source_and_rebuilt_library_are_safe():
    source = os.path.join(HOME, "parser.c")
    installed_lib = os.path.join(HOME, "libparser.so")
    assert os.path.isfile(source), "parser.c is missing."
    assert os.path.isfile(installed_lib), "libparser.so is missing."

    with tempfile.TemporaryDirectory() as td:
        rebuilt_from_source = os.path.join(td, "libparser_from_source.so")
        result = subprocess.run(
            ["gcc", "-shared", "-fPIC", source, "-o", rebuilt_from_source],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        assert result.returncode == 0, f"Modified parser.c does not compile: {result.stderr}"
        exercise_parser_library(rebuilt_from_source)

    exercise_parser_library(installed_lib)


def test_binary_processes_derived_payload_to_completion():
    binary = os.path.join(HOME, "data_exfiltrator")
    library = os.path.join(HOME, "libparser.so")
    assert os.path.isfile(binary) and os.access(binary, os.X_OK), "data_exfiltrator is missing or not executable."
    assert os.path.isfile(library), "libparser.so is missing."

    base = 1700000000 + secrets.randbelow(1000000)
    timestamps = [base + i * 17 for i in range(8)]
    normal = [("record_" + secrets.token_hex(10)).encode("ascii") for _ in range(7)]
    oversized = "".join(secrets.choice("ABCDEFGHIJKLMNOPQRSTUVWXYZ") for _ in range(300)).encode("ascii")
    payload_records = [
        normal[0], normal[1], normal[2], normal[3], normal[4], oversized, normal[5], normal[6]
    ]

    with tempfile.TemporaryDirectory() as td:
        payload_path = os.path.join(td, "derived_payload.bin")
        with open(payload_path, "wb") as f:
            for ts, data in zip(timestamps, payload_records):
                f.write(struct.pack(">IH", ts, len(data)))
                f.write(data)

        env = os.environ.copy()
        env["LD_LIBRARY_PATH"] = HOME + (":" + env["LD_LIBRARY_PATH"] if env.get("LD_LIBRARY_PATH") else "")
        result = subprocess.run(
            [binary, payload_path],
            cwd=td,
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=15,
        )
        assert result.returncode == 0, (
            f"data_exfiltrator did not complete successfully (return code {result.returncode}).\n"
            f"stderr: {result.stderr.decode(errors='replace')}"
        )

        db_path = os.path.join(td, "stolen_data.db")
        assert os.path.isfile(db_path), "The binary did not create stolen_data.db."
        conn = sqlite3.connect(db_path)
        try:
            rows = conn.execute(
                "SELECT timestamp, data FROM exfiltration_logs ORDER BY timestamp"
            ).fetchall()
            integrity = conn.execute("PRAGMA integrity_check").fetchone()[0]
        finally:
            conn.close()

        expected = []
        for i, (ts, data) in enumerate(zip(timestamps, payload_records)):
            expected_data = data[:255] if i == 5 else data
            expected.append((ts, expected_data.decode("ascii")))
        assert integrity == "ok", f"Generated database failed integrity_check: {integrity}"
        assert rows == expected, "The binary did not parse and insert the derived records correctly."


def test_report_content():
    report_path = "/home/user/report.txt"
    assert os.path.exists(report_path), f"Expected report file {report_path} does not exist."

    with open(report_path, "r") as f:
        content = f.read().strip()

    expected_content = "Targeted Service: sshd\nTotal Records: 8"
    assert content == expected_content, (
        f"Content of {report_path} is incorrect.\n"
        f"Expected:\n{expected_content}\n"
        f"Got:\n{content}"
    )


def test_database_records():
    db_path = "/home/user/stolen_data.db"
    assert os.path.exists(db_path), f"Database file {db_path} does not exist."

    wal_path = db_path + "-wal"
    assert not os.path.exists(wal_path) or os.path.getsize(wal_path) == 0, (
        "stolen_data.db still has a non-empty WAL and was not fully recovered/checkpointed."
    )

    try:
        conn = sqlite3.connect(db_path)
        cursor = conn.cursor()

        # Check total records
        cursor.execute("SELECT COUNT(*) FROM exfiltration_logs;")
        count = cursor.fetchone()[0]
        assert count == 8, f"Expected 8 records in exfiltration_logs table, but found {count}."

        # Check earliest timestamp
        cursor.execute("SELECT MIN(timestamp) FROM exfiltration_logs;")
        min_ts = cursor.fetchone()[0]
        assert min_ts == 1680000000, f"Expected minimum timestamp to be 1680000000, but found {min_ts}."

        # Ensure the 6th record (which was oversized) was properly truncated and inserted
        cursor.execute("SELECT data FROM exfiltration_logs WHERE timestamp = 1680000075;")
        oversized_data = cursor.fetchone()
        assert oversized_data is not None, "The oversized record was not found in the database."
        assert len(oversized_data[0]) <= 255, "The oversized record was not properly truncated to fit within 255 bytes."

        expected_rows = [
            (1680000000, "record1_normal"),
            (1680000015, "record2_normal"),
            (1680000030, "record3_normal"),
            (1680000045, "record4_normal"),
            (1680000060, "record5_normal"),
            (1680000075, "A" * 255),
            (1680000090, "record7_normal"),
            (1680000105, "record8_normal"),
        ]
        cursor.execute("SELECT timestamp, data FROM exfiltration_logs ORDER BY timestamp;")
        assert cursor.fetchall() == expected_rows, "Database contents do not match the processed payload."
        assert cursor.execute("PRAGMA integrity_check;").fetchone()[0] == "ok", "Database integrity check failed."

    except sqlite3.OperationalError as e:
        pytest.fail(f"Failed to query the database. Is the schema correct? Error: {e}")
    finally:
        if 'conn' in locals():
            conn.close()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
