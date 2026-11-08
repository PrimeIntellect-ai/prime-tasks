#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import socket
import sqlite3
import struct
import time
import zlib

import pytest

DB_PATH = "/home/user/telemetry.db"
SOURCE_PATH = "/home/user/ingester/src/main.rs"
HOST = "127.0.0.1"
PORT = 9999


def compute_checksum(payload: bytes) -> int:
    return (zlib.crc32(payload) & 0xFFFFFFFF) ^ 0x87654321


def make_packet(payload_dict: dict, valid: bool = True) -> bytes:
    payload = json.dumps(payload_dict).encode("utf-8")
    checksum = compute_checksum(payload)
    if not valid:
        checksum ^= 0xFFFFFFFF
    return struct.pack("<II", len(payload), checksum) + payload


def send_packet(packet: bytes, require_disconnect: bool = False):
    try:
        with socket.create_connection((HOST, PORT), timeout=3) as sock:
            sock.settimeout(3)
            sock.sendall(packet)
            if require_disconnect:
                try:
                    response = sock.recv(1)
                    assert response == b"", "Expected invalid packet connection to be dropped"
                except (ConnectionResetError, BrokenPipeError):
                    pass
                except socket.timeout:
                    pytest.fail("Server did not promptly drop an invalid packet connection")
    except ConnectionRefusedError:
        pytest.fail(f"Could not connect to {HOST}:{PORT}. Is the server running?")


def wait_for_rows(expected, timeout=5):
    deadline = time.time() + timeout
    while time.time() < deadline:
        with sqlite3.connect(DB_PATH) as conn:
            found = {
                row[0]: row[1]
                for row in conn.execute(
                    "SELECT device_id, temperature FROM readings_v2 WHERE device_id IN (%s)"
                    % ",".join("?" for _ in expected),
                    tuple(expected),
                )
            }
        if all(device in found for device in expected):
            return found
        time.sleep(0.05)
    return found


def listener_pid():
    wanted_inode = None
    for proc_file in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(proc_file) as fh:
                next(fh)
                for line in fh:
                    fields = line.split()
                    local, state = fields[1], fields[3]
                    if int(local.rsplit(":", 1)[1], 16) == PORT and state == "0A":
                        wanted_inode = fields[9]
                        break
        except OSError:
            continue
        if wanted_inode:
            break
    assert wanted_inode, f"No listening socket found on port {PORT}"

    target = f"socket:[{wanted_inode}]"
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        fd_dir = f"/proc/{pid}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    if os.readlink(f"{fd_dir}/{fd}") == target:
                        return int(pid)
                except OSError:
                    pass
        except OSError:
            pass
    pytest.fail("Could not identify the process listening on port 9999")


def rss_kib(pid):
    with open(f"/proc/{pid}/status") as fh:
        for line in fh:
            if line.startswith("VmRSS:"):
                return int(line.split()[1])
    pytest.fail(f"Could not read RSS for server process {pid}")


def test_db_migration():
    assert os.path.exists(DB_PATH), f"Database {DB_PATH} missing."
    with sqlite3.connect(DB_PATH) as conn:
        assert conn.execute(
            "SELECT 1 FROM sqlite_master WHERE type='table' AND name='readings_v2'"
        ).fetchone(), "Table 'readings_v2' was not created."

        info = conn.execute("PRAGMA table_info(readings_v2)").fetchall()
        assert len(info) == 3, f"readings_v2 must have exactly three columns, found: {info}"
        normalized = [(r[1], r[2].upper(), r[5]) for r in info]
        assert normalized == [
            ("id", "INTEGER", 1),
            ("device_id", "INTEGER", 0),
            ("temperature", "REAL", 0),
        ], f"Incorrect readings_v2 schema: {info}"

        row = conn.execute(
            "SELECT id, device_id, temperature FROM readings_v2 WHERE id=1"
        ).fetchone()
        assert row == (1, 100, 42.5), f"Migrated row incorrect: {row}"

        old_rows = conn.execute(
            "SELECT id, dev_id, metric FROM readings_v1 ORDER BY id"
        ).fetchall()
        for old_row in old_rows:
            migrated = conn.execute(
                "SELECT id, device_id, temperature FROM readings_v2 "
                "WHERE id=? AND device_id=? AND temperature=?",
                old_row,
            ).fetchone()
            assert migrated == old_row, f"Existing row was not migrated correctly: {old_row}"


def test_running_artifact_and_no_explicit_leak_primitive():
    assert os.path.isfile(SOURCE_PATH), "Rust server source is missing"
    source = open(SOURCE_PATH, encoding="utf-8").read().replace(" ", "")
    forbidden = ("Box::leak", "Vec::leak", "std::mem::forget", "mem::forget")
    assert not any(token in source for token in forbidden), "Server source still explicitly leaks packet buffers"

    pid = listener_pid()
    executable = os.path.realpath(f"/proc/{pid}/exe")
    assert executable.startswith("/home/user/ingester/"), (
        f"Port 9999 is not served by the compiled ingester artifact: {executable}"
    )


def test_tcp_server_original_fixed_cases():
    with sqlite3.connect(DB_PATH) as conn:
        before = conn.execute(
            "SELECT COUNT(*) FROM readings_v2 WHERE device_id=999"
        ).fetchone()[0]

    send_packet(make_packet({"device": 999, "temp": 123.45}, True))
    found = wait_for_rows({999})
    assert found.get(999) == 123.45, "Valid fixed-case packet was not inserted correctly"

    with sqlite3.connect(DB_PATH) as conn:
        after = conn.execute(
            "SELECT COUNT(*) FROM readings_v2 WHERE device_id=999"
        ).fetchone()[0]
    assert after == before + 1, "Valid packet did not create exactly one reading"

    send_packet(make_packet({"device": 888, "temp": 54.32}, False), require_disconnect=True)
    time.sleep(0.2)
    with sqlite3.connect(DB_PATH) as conn:
        row = conn.execute(
            "SELECT device_id FROM readings_v2 WHERE device_id=888"
        ).fetchone()
    assert row is None, "Invalid fixed-case packet was incorrectly inserted"


def test_randomized_checksum_and_integration():
    with sqlite3.connect(DB_PATH) as conn:
        used = {r[0] for r in conn.execute("SELECT device_id FROM readings_v2")}

    valid_cases = {}
    while len(valid_cases) < 12:
        device = secrets.randbelow(1_500_000_000) + 10000
        if device not in used and device not in valid_cases:
            valid_cases[device] = (secrets.randbelow(2000001) - 1000000) / 100.0

    invalid_cases = {}
    while len(invalid_cases) < 10:
        device = secrets.randbelow(1_500_000_000) + 1_600_000_000
        if device not in used and device not in invalid_cases:
            invalid_cases[device] = (secrets.randbelow(2000001) - 1000000) / 100.0

    for device, temperature in valid_cases.items():
        send_packet(make_packet({"device": device, "temp": temperature}, True))

    found = wait_for_rows(valid_cases)
    for device, temperature in valid_cases.items():
        assert device in found, f"Valid randomized packet for device {device} was not inserted"
        assert found[device] == pytest.approx(temperature), f"Wrong value inserted for device {device}"

    for device, temperature in invalid_cases.items():
        send_packet(make_packet({"device": device, "temp": temperature}, False), require_disconnect=True)

    time.sleep(0.3)
    with sqlite3.connect(DB_PATH) as conn:
        placeholders = ",".join("?" for _ in invalid_cases)
        bad = conn.execute(
            f"SELECT device_id FROM readings_v2 WHERE device_id IN ({placeholders})",
            tuple(invalid_cases),
        ).fetchall()
    assert not bad, f"Invalid randomized packets were inserted: {bad}"


def test_packet_buffers_do_not_leak_per_request():
    pid = listener_pid()
    target_size = 256 * 1024
    prefix = b'{"device":424242,"temp":1.25}'
    payload = prefix + (b" " * (target_size - len(prefix)))
    invalid_checksum = compute_checksum(payload) ^ 0xFFFFFFFF
    packet = struct.pack("<II", len(payload), invalid_checksum) + payload

    # Warm up allocator and networking before taking the baseline.
    for _ in range(12):
        send_packet(packet)
    time.sleep(0.4)
    baseline = rss_kib(pid)

    for _ in range(160):
        send_packet(packet)
    time.sleep(0.8)

    assert listener_pid() == pid, "Server exited or was replaced during memory test"
    growth = rss_kib(pid) - baseline
    assert growth < 18 * 1024, (
        f"Server RSS grew by {growth} KiB while processing packet buffers; "
        "the per-request memory leak remains"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
