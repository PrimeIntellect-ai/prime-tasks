#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import py_compile
import secrets
import struct
import subprocess

import pytest

RECOVERY = "/home/user/recovery.py"
WAL = "/home/user/db/transaction.wal"
REPORT = "/home/user/recovery_report.txt"


def derive_expected(wal_bytes):
    offset = 0
    corrupted = []
    total = 0
    while offset < len(wal_bytes):
        assert len(wal_bytes) - offset >= 8, "Verifier WAL has a truncated header"
        txid, length = struct.unpack_from("<II", wal_bytes, offset)
        offset += 8
        assert len(wal_bytes) - offset >= length, "Verifier WAL has a truncated payload"
        payload = wal_bytes[offset:offset + length]
        offset += length
        try:
            text = payload.decode("utf-8")
        except UnicodeDecodeError:
            corrupted.append(txid)
            continue
        data = json.loads(text)
        if "value" in data:
            total += data["value"]
    return corrupted, total


def run_recovery_and_check(wal_bytes):
    corrupted, total = derive_expected(wal_bytes)
    assert len(corrupted) == 1

    with open(WAL, "wb") as f:
        f.write(wal_bytes)
    if os.path.exists(REPORT):
        os.remove(REPORT)

    result = subprocess.run(
        ["python3", RECOVERY],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"recovery.py failed with exit code {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(REPORT), f"The file {REPORT} does not exist after running recovery.py."
    with open(REPORT, "r", encoding="utf-8") as f:
        content = f.read().strip()
    expected = f"Corrupted TxID: {corrupted[0]}\nRecovered Total: {total}"
    assert content == expected, f"Expected report {expected!r}, got {content!r}."


def record(txid, payload):
    return struct.pack("<II", txid, len(payload)) + payload


@pytest.fixture(scope="session", autouse=True)
def execute_canonical_recovery():
    assert os.path.isfile(RECOVERY), f"The file {RECOVERY} does not exist."
    assert not os.path.islink(RECOVERY), f"The file {RECOVERY} must be a real Python source file."
    py_compile.compile(RECOVERY, doraise=True)

    with open(WAL, "rb") as f:
        original_wal = f.read()
    try:
        run_recovery_and_check(original_wal)
        yield original_wal
    finally:
        with open(WAL, "wb") as f:
            f.write(original_wal)


def test_recovery_report_exists():
    """Check if the recovery report was generated."""
    report_file = "/home/user/recovery_report.txt"
    assert os.path.isfile(report_file), f"The file {report_file} does not exist."


def test_recovery_report_content():
    """Check if the recovery report contains the correct values."""
    report_file = "/home/user/recovery_report.txt"
    with open(report_file, "r") as f:
        content = f.read().strip()

    expected_txid_line = "Corrupted TxID: 3"
    expected_total_line = "Recovered Total: 500"

    assert expected_txid_line in content, "The report does not contain the correct Corrupted TxID or the format is incorrect."
    assert expected_total_line in content, "The report does not contain the correct Recovered Total or the format is incorrect."

    lines = [line.strip() for line in content.split('\n') if line.strip()]
    assert len(lines) >= 2, "The report should contain at least two lines."
    assert lines[0] == expected_txid_line, f"Expected first line to be '{expected_txid_line}', got '{lines[0]}'."
    assert lines[1] == expected_total_line, f"Expected second line to be '{expected_total_line}', got '{lines[1]}'."


def test_recovery_handles_derived_wals(execute_canonical_recovery):
    used = set()
    for _ in range(2):
        ids = []
        while len(ids) < 4:
            candidate = 1000 + secrets.randbelow(2_000_000_000)
            if candidate not in used:
                used.add(candidate)
                ids.append(candidate)
        values = [1 + secrets.randbelow(100000) for _ in range(3)]
        wal = b"".join([
            record(ids[0], json.dumps({"value": values[0]}).encode("utf-8")),
            record(ids[1], b'{"value": 999999, "data": "\xff\xfe"}'),
            record(ids[2], json.dumps({"value": values[1], "data": "ok"}).encode("utf-8")),
            record(ids[3], json.dumps({"value": values[2]}).encode("utf-8")),
        ])
        run_recovery_and_check(wal)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
