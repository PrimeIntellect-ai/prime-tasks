#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import datetime
import importlib.util
import os
import re
import secrets
import shutil
import sqlite3
import tempfile

import pytest
from scapy.all import Raw, rdpcap

BASE_DIR = "/home/user/ticket4092"
LOG_FILE = os.path.join(BASE_DIR, "service.log")
DB_FILE = os.path.join(BASE_DIR, "market_data.db")
PCAP_FILE = os.path.join(BASE_DIR, "traffic.pcap")
SERVICE_FILE = os.path.join(BASE_DIR, "vwap_service.py")
RESOLUTION_FILE = os.path.join(BASE_DIR, "resolution.txt")
EXPECTED_URI = "/vwap?start=2023-10-27T14:00:00Z&end=2023-10-27T15:00:00Z"


def pcap_request():
    assert os.path.isfile(PCAP_FILE), f"Packet capture {PCAP_FILE} is missing."
    requests = []
    for packet in rdpcap(PCAP_FILE):
        if Raw not in packet:
            continue
        payload = bytes(packet[Raw].load)
        match = re.search(rb"GET ([^ ]+) HTTP/1\\.[01]\\r?\\n", payload)
        if match:
            requests.append(match.group(1).decode("ascii"))

    assert requests, "No HTTP GET request was found in traffic.pcap."
    assert EXPECTED_URI in requests, "traffic.pcap does not contain the supplied analyst request."

    match = re.fullmatch(r"/vwap\?start=([^&]+)&end=([^&]+)", EXPECTED_URI)
    assert match is not None
    return EXPECTED_URI, match.group(1), match.group(2)


def database_vwap(db_path, start, end):
    conn = sqlite3.connect(db_path)
    try:
        rows = conn.execute(
            "SELECT price, volume FROM trades WHERE timestamp >= ? AND timestamp <= ?",
            (start, end),
        ).fetchall()
    finally:
        conn.close()
    total_value = sum(price * volume for price, volume in rows)
    total_volume = sum(volume for price, volume in rows)
    assert total_volume > 0, "No data found for the expected time range in the database."
    return total_value / total_volume


def load_service():
    assert os.path.isfile(SERVICE_FILE), f"Service implementation {SERVICE_FILE} is missing."
    spec = importlib.util.spec_from_file_location("submitted_vwap_service", SERVICE_FILE)
    assert spec is not None and spec.loader is not None, "vwap_service.py is not importable Python."
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert callable(getattr(module, "calculate_vwap", None)), "calculate_vwap is missing or not callable."
    return module


def test_resolution_report_exists_and_correct():
    assert os.path.isfile(RESOLUTION_FILE), f"Resolution report {RESOLUTION_FILE} is missing."

    request_uri, expected_start, expected_end = pcap_request()

    # Preserve the original log assertions, while using the packet capture as truth.
    assert os.path.isfile(LOG_FILE), f"Log file {LOG_FILE} is missing."
    with open(LOG_FILE, "r") as f:
        log_content = f.read()
    log_match = re.search(r"GET /vwap\?start=([^&]+)&end=([^\s]+)", log_content)
    assert log_match is not None, "Could not find the original GET request in service.log."
    assert log_match.group(1) == expected_start
    assert log_match.group(2) == expected_end
    assert request_uri == f"/vwap?start={expected_start}&end={expected_end}"

    assert os.path.isfile(DB_FILE), f"Database file {DB_FILE} is missing."
    expected_vwap = round(database_vwap(DB_FILE, expected_start, expected_end), 4)

    with open(RESOLUTION_FILE, "r") as f:
        res_content = f.read()

    start_match = re.search(r"Requested Start:\s*(.+)", res_content)
    end_match = re.search(r"Requested End:\s*(.+)", res_content)
    vwap_match = re.search(r"Correct VWAP:\s*(.+)", res_content)

    assert start_match is not None, "Format error: 'Requested Start: <value>' not found in resolution.txt."
    assert end_match is not None, "Format error: 'Requested End: <value>' not found in resolution.txt."
    assert vwap_match is not None, "Format error: 'Correct VWAP: <value>' not found in resolution.txt."

    actual_start = start_match.group(1).strip()
    actual_end = end_match.group(1).strip()
    try:
        actual_vwap = float(vwap_match.group(1).strip())
    except ValueError:
        pytest.fail("Format error: VWAP value in resolution.txt is not a valid float.")

    assert actual_start == expected_start, f"Requested Start is incorrect. Expected {expected_start}, got {actual_start}."
    assert actual_end == expected_end, f"Requested End is incorrect. Expected {expected_end}, got {actual_end}."
    assert actual_vwap == expected_vwap, f"Correct VWAP is incorrect. Expected {expected_vwap}, got {actual_vwap}."


def test_fixed_service_executes_and_handles_utc_inputs():
    module = load_service()
    _, requested_start, requested_end = pcap_request()

    expected = database_vwap(DB_FILE, requested_start, requested_end)
    actual = module.calculate_vwap(requested_start, requested_end)
    assert isinstance(actual, (int, float)), "calculate_vwap must return a numeric value."
    assert actual == pytest.approx(expected, rel=1e-12, abs=1e-12)

    backup = tempfile.NamedTemporaryFile(prefix="market_data_backup_", suffix=".db", delete=False)
    backup.close()
    shutil.copy2(DB_FILE, backup.name)

    try:
        for case in range(3):
            base = datetime.datetime(
                2021 + secrets.randbelow(5),
                1,
                5 + secrets.randbelow(15),
                secrets.randbelow(18),
                secrets.randbelow(30),
                tzinfo=datetime.timezone.utc,
            )
            start_dt = base
            end_dt = base + datetime.timedelta(hours=1)
            start = start_dt.strftime("%Y-%m-%dT%H:%M:%SZ")
            end = end_dt.strftime("%Y-%m-%dT%H:%M:%SZ")

            rows = []
            for minute in (0, 17, 43, 60):
                ts = (base + datetime.timedelta(minutes=minute)).strftime("%Y-%m-%dT%H:%M:%SZ")
                price = 20.0 + secrets.randbelow(20000) / 100.0
                volume = 1 + secrets.randbelow(500)
                rows.append((ts, price, volume))

            # Decoys at the five-hour offset produced by the original Eastern-time bug.
            for minute in (300, 320, 355):
                ts = (base + datetime.timedelta(minutes=minute)).strftime("%Y-%m-%dT%H:%M:%SZ")
                rows.append((ts, 500.0 + case, 700 + case))

            if os.path.exists(DB_FILE):
                os.remove(DB_FILE)
            conn = sqlite3.connect(DB_FILE)
            try:
                conn.execute("CREATE TABLE trades (timestamp TEXT, price REAL, volume INTEGER)")
                conn.executemany("INSERT INTO trades VALUES (?, ?, ?)", rows)
                conn.commit()
            finally:
                conn.close()

            expected = database_vwap(DB_FILE, start, end)
            actual = module.calculate_vwap(start, end)
            assert isinstance(actual, (int, float)), "calculate_vwap must return a numeric value."
            assert actual == pytest.approx(expected, rel=1e-12, abs=1e-12), (
                f"calculate_vwap queried the wrong UTC interval for {start} through {end}."
            )
    finally:
        shutil.copy2(backup.name, DB_FILE)
        os.unlink(backup.name)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
