#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import sqlite3
import pytest
import json
import csv
import xml.etree.ElementTree as ET
import hashlib

DB_PATH = "/home/user/master_config.db"

def compute_expected_records():
    """Derive the expected records from the input files according to the rules."""
    records = []

    # 1. snapA.json
    json_path = "/home/user/inputs/snapA.json"
    if os.path.exists(json_path):
        with open(json_path, "r") as f:
            data = json.load(f)
            for row in data:
                records.append({
                    "server_id": str(row.get("server_id", "")),
                    "service": str(row.get("service", "")),
                    "port": int(row.get("port", 0)),
                    "status": str(row.get("status", "")),
                    "config_string": str(row.get("config_string", ""))
                })

    # 2. snapB.csv
    csv_path = "/home/user/inputs/snapB.csv"
    if os.path.exists(csv_path):
        with open(csv_path, "r") as f:
            reader = csv.DictReader(f)
            for row in reader:
                records.append({
                    "server_id": str(row.get("server_id", "")),
                    "service": str(row.get("service", "")),
                    "port": int(row.get("port", 0)),
                    "status": str(row.get("status", "")),
                    "config_string": str(row.get("config_string", ""))
                })

    # 3. snapC.xml
    xml_path = "/home/user/inputs/snapC.xml"
    if os.path.exists(xml_path):
        tree = ET.parse(xml_path)
        root = tree.getroot()
        for config in root.findall("config"):
            records.append({
                "server_id": str(config.findtext("server_id", "")),
                "service": str(config.findtext("service", "")),
                "port": int(config.findtext("port", 0)),
                "status": str(config.findtext("status", "")),
                "config_string": str(config.findtext("config_string", ""))
            })

    valid_records = []
    seen_hashes = set()

    for r in records:
        # Constraint Validation
        if not (1024 <= r["port"] <= 65535):
            continue
        if r["status"] not in ("active", "inactive"):
            continue

        # Hash-Based Deduplication
        hash_input = f"{r['server_id']}|{r['service']}|{r['config_string']}"
        md5_hash = hashlib.md5(hash_input.encode('utf-8')).hexdigest()

        if md5_hash not in seen_hashes:
            seen_hashes.add(md5_hash)
            valid_records.append((
                r["server_id"],
                r["service"],
                r["port"],
                r["status"],
                r["config_string"],
                md5_hash
            ))

    return valid_records

def test_database_exists():
    assert os.path.exists(DB_PATH), f"Database file not found at {DB_PATH}"

def test_table_schema():
    assert os.path.exists(DB_PATH), f"Database file not found at {DB_PATH}"
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    cursor.execute("PRAGMA table_info(valid_configs);")
    columns = cursor.fetchall()
    conn.close()

    assert len(columns) > 0, "Table 'valid_configs' does not exist."

    expected_schema = [
        ("server_id", "TEXT"),
        ("service", "TEXT"),
        ("port", "INTEGER"),
        ("status", "TEXT"),
        ("config_string", "TEXT"),
        ("config_hash", "TEXT")
    ]

    actual_schema = [(col[1], col[2].upper()) for col in columns]
    for exp_col, exp_type in expected_schema:
        assert (exp_col, exp_type) in actual_schema, f"Missing or incorrect column: {exp_col} {exp_type}. Found: {actual_schema}"

def test_database_records():
    assert os.path.exists(DB_PATH), f"Database file not found at {DB_PATH}"
    expected_records = compute_expected_records()

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    try:
        cursor.execute("SELECT server_id, service, port, status, config_string, config_hash FROM valid_configs ORDER BY server_id;")
        actual_records = cursor.fetchall()
    except sqlite3.OperationalError as e:
        pytest.fail(f"Failed to query valid_configs table: {e}")
    finally:
        conn.close()

    expected_records_sorted = sorted(expected_records, key=lambda x: x[0])

    assert len(actual_records) == len(expected_records_sorted), f"Expected {len(expected_records_sorted)} records, found {len(actual_records)}."

    for i, (actual, expected) in enumerate(zip(actual_records, expected_records_sorted)):
        assert actual == expected, f"Record mismatch at index {i}.\nExpected: {expected}\nGot: {actual}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
