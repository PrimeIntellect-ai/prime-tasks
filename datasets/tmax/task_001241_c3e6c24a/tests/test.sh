#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import sqlite3
import socket
import struct
import subprocess
import time
import uuid

import pytest

REPO = "/home/user/app/repo"
RECOVERED = "/home/user/recovered.db"
SOURCE_WAL = "/home/user/corrupted_env/data.db-wal"
APP_DB = "/home/user/app/data.db"


def read_varint(buf, offset):
    value = 0
    for i in range(9):
        assert offset + i < len(buf), "Truncated SQLite varint"
        byte = buf[offset + i]
        if i == 8:
            return (value << 8) | byte, offset + 9
        value = (value << 7) | (byte & 0x7f)
        if not (byte & 0x80):
            return value, offset + i + 1
    raise AssertionError("Invalid SQLite varint")


def decode_serial(buf, offset, serial):
    if serial == 0:
        return None, offset
    lengths = {1: 1, 2: 2, 3: 3, 4: 4, 5: 6, 6: 8}
    if serial in lengths:
        n = lengths[serial]
        raw = buf[offset:offset+n]
        assert len(raw) == n
        return int.from_bytes(raw, "big", signed=True), offset + n
    if serial == 7:
        raw = buf[offset:offset+8]
        assert len(raw) == 8
        return struct.unpack(">d", raw)[0], offset + 8
    if serial == 8:
        return 0, offset
    if serial == 9:
        return 1, offset
    if serial in (10, 11):
        raise AssertionError("Reserved SQLite serial type")
    if serial >= 12:
        n = (serial - 12) // 2 if serial % 2 == 0 else (serial - 13) // 2
        raw = buf[offset:offset+n]
        assert len(raw) == n
        if serial % 2:
            return raw.decode("utf-8"), offset + n
        return bytes(raw), offset + n
    raise AssertionError(f"Unknown serial type {serial}")


def decode_record(payload):
    header_size, pos = read_varint(payload, 0)
    assert 0 < header_size <= len(payload)
    serials = []
    while pos < header_size:
        serial, pos = read_varint(payload, pos)
        serials.append(serial)
    assert pos == header_size
    body = header_size
    values = []
    for serial in serials:
        value, body = decode_serial(payload, body, serial)
        values.append(value)
    return values


def telemetry_rows_from_wal(path):
    assert os.path.isfile(path), f"Original forensic WAL is missing: {path}"
    data = open(path, "rb").read()
    assert len(data) >= 32, "Forensic WAL is truncated"
    magic = struct.unpack(">I", data[:4])[0]
    assert magic in (0x377f0682, 0x377f0683), "Invalid SQLite WAL header"
    page_size = struct.unpack(">I", data[8:12])[0]
    if page_size == 1:
        page_size = 65536
    assert page_size >= 512 and page_size & (page_size - 1) == 0

    frame_size = 24 + page_size
    frame_count = (len(data) - 32) // frame_size
    assert frame_count > 0, "Forensic WAL contains no complete frames"
    frames = []
    last_commit = -1
    db_pages = 0
    for i in range(frame_count):
        start = 32 + i * frame_size
        page_no, commit_pages = struct.unpack(">II", data[start:start+8])
        assert page_no > 0
        frames.append((page_no, data[start+24:start+frame_size]))
        if commit_pages:
            last_commit = i
            db_pages = commit_pages
    assert last_commit >= 0, "Forensic WAL has no committed transaction"

    pages = {}
    for page_no, page in frames[:last_commit+1]:
        if page_no <= db_pages:
            pages[page_no] = page

    rows = {}
    for page_no, page in pages.items():
        header = 100 if page_no == 1 else 0
        if len(page) < header + 8 or page[header] != 0x0d:
            continue
        cell_count = struct.unpack(">H", page[header+3:header+5])[0]
        for i in range(cell_count):
            pointer_pos = header + 8 + 2 * i
            assert pointer_pos + 2 <= len(page)
            cell = struct.unpack(">H", page[pointer_pos:pointer_pos+2])[0]
            assert 0 <= cell < len(page)
            payload_size, pos = read_varint(page, cell)
            rowid, pos = read_varint(page, pos)
            # Telemetry records are small enough to be stored locally in full.
            if pos + payload_size > len(page):
                continue
            values = decode_record(page[pos:pos+payload_size])
            if (len(values) == 3 and values[0] is None and
                    isinstance(values[1], str) and
                    isinstance(values[2], (int, float))):
                rows[rowid] = (values[1], float(values[2]))
    return rows


def test_recovered_database_row_count_and_contents():
    assert os.path.isfile(RECOVERED), f"Recovered database not found at {RECOVERED}"
    expected = telemetry_rows_from_wal(SOURCE_WAL)
    assert len(expected) == 5000, f"Expected 5000 recoverable WAL rows, decoded {len(expected)}"

    try:
        conn = sqlite3.connect(f"file:{RECOVERED}?mode=ro", uri=True)
        integrity = conn.execute("PRAGMA integrity_check").fetchone()[0]
        assert integrity == "ok", f"Recovered database failed integrity check: {integrity}"
        schema = conn.execute("PRAGMA table_info(telemetry)").fetchall()
        assert schema == [
            (0, "id", "INTEGER", 0, None, 1),
            (1, "sensor", "TEXT", 0, None, 0),
            (2, "value", "REAL", 0, None, 0),
        ], f"Unexpected telemetry schema: {schema}"
        count = conn.execute("SELECT count(*) FROM telemetry").fetchone()[0]
        assert count >= 4800, f"Recovered database has {count} rows, expected at least 4800."
        actual_rows = conn.execute(
            "SELECT id, sensor, value FROM telemetry ORDER BY id"
        ).fetchall()
        conn.close()
    except sqlite3.Error as exc:
        pytest.fail(f"Failed to query the recovered database: {exc}")

    actual = {rowid: (sensor, float(value)) for rowid, sensor, value in actual_rows}
    assert len(actual_rows) == len(actual), "Recovered database contains duplicate IDs"
    assert actual == expected, "Recovered rows do not match the committed records stranded in the WAL"


def wait_for_port(timeout=8):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", 8080), timeout=0.5):
                return
        except OSError:
            time.sleep(0.1)
    pytest.fail("API server did not start listening on port 8080")


def send_record(sensor, value):
    payload = f"{sensor},{value}\n".encode("utf-8")
    try:
        with socket.create_connection(("127.0.0.1", 8080), timeout=2) as sock:
            sock.sendall(payload)
    except Exception as exc:
        pytest.fail(f"Failed to send data to API server on port 8080: {exc}")


def test_regression_and_pipeline_end_to_end():
    worker = os.path.join(REPO, "worker.sh")
    starter = os.path.join(REPO, "start_services.sh")
    assert os.path.isfile(worker) and os.access(worker, os.X_OK), "worker.sh is missing or not executable"
    assert os.path.isfile(starter) and os.access(starter, os.X_OK), "start_services.sh is missing or not executable"
    subprocess.run(["bash", "-n", worker], check=True)

    commits = subprocess.check_output(
        ["git", "-C", REPO, "log", "--all", "--format=%H%x00%s"], text=True
    ).splitlines()
    bad = [line.split("\x00", 1)[0] for line in commits if line.endswith("\x00Update worker logic")]
    assert len(bad) == 1, "Could not uniquely identify the regression commit"
    bad_worker = subprocess.check_output(
        ["git", "-C", REPO, "show", f"{bad[0]}:worker.sh"], text=True
    )
    parent_worker = subprocess.check_output(
        ["git", "-C", REPO, "show", f"{bad[0]}^:worker.sh"], text=True
    )
    assert 'while [ "$val" -lt 0 ]' in bad_worker
    assert 'while [ "$val" -lt 0 ]' not in parent_worker
    current_worker = open(worker, encoding="utf-8").read()
    assert current_worker != bad_worker, "worker.sh is still the regressed version"
    assert subprocess.run(
        ["git", "-C", REPO, "merge-base", "--is-ancestor", bad[0], "HEAD"]
    ).returncode == 0, "Current checkout is not based on the branch containing the regression"
    assert re.search(r"(?:^|\n)\s*nohup\s+\./worker\.sh\b", open(starter).read()), \
        "start_services.sh no longer starts worker.sh"

    # Remove any pre-existing listeners and records, then execute the submitted service artifacts.
    subprocess.run(
        ["pkill", "-f", "api_server.sh|worker.sh|TCP4-LISTEN:8080|tail -F /home/user/app/spool.log"],
        check=False,
    )
    time.sleep(0.4)
    for suffix in ("", "-wal", "-shm"):
        try:
            os.remove(APP_DB + suffix)
        except FileNotFoundError:
            pass
    try:
        os.remove("/home/user/app/spool.log")
    except FileNotFoundError:
        pass

    subprocess.run(["bash", "./start_services.sh"], cwd=REPO, check=True, timeout=8)
    wait_for_port()
    time.sleep(0.5)
    assert os.path.isfile(APP_DB), f"Application database not found at {APP_DB}"

    token = uuid.uuid4().hex
    test_records = [
        ("sensorX", 99.9),
        ("sensorY", -5.0),
        (f"negative_{token}", -731.25),
        (f"after_negative_{token}", 18.625),
        (f"normal_{token}", 42.125),
    ]
    for sensor, value in test_records:
        send_record(sensor, value)

    deadline = time.time() + 10
    found = {}
    while time.time() < deadline:
        try:
            conn = sqlite3.connect(APP_DB, timeout=1)
            for sensor, value in test_records:
                count = conn.execute(
                    "SELECT count(*) FROM telemetry WHERE sensor = ? AND value = ?",
                    (sensor, value),
                ).fetchone()[0]
                found[(sensor, value)] = count
            conn.close()
        except sqlite3.Error:
            pass
        if all(found.get(record, 0) > 0 for record in test_records):
            break
        time.sleep(0.2)

    for sensor, value in test_records:
        assert found.get((sensor, value), 0) > 0, (
            f"Record for {sensor} with value {value} was not found in the database. "
            "Pipeline might be hanging or dropping data."
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
