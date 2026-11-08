#!/bin/bash
set -u
mkdir -p /logs/verifier

fail() {
    echo "0" > /logs/verifier/reward.txt
    exit 0
}

SCRIPT=/home/user/etl/etl_pipeline.py
LOG_PATH=/home/user/etl/pipeline.log
OUTPUT_PATH=/home/user/etl/output/clean_transactions.jsonl
INPUT_DIR=/home/user/etl/input

[ -f "$SCRIPT" ] || fail
[ -x "$SCRIPT" ] || fail

rm -f "$LOG_PATH" "$OUTPUT_PATH"
timeout 20s python3 "$SCRIPT" || fail

cat << 'TEST_EOF' > /tmp/test_original_state.py
import json
import os
import pytest

LOG_PATH = "/home/user/etl/pipeline.log"
OUTPUT_PATH = "/home/user/etl/output/clean_transactions.jsonl"


def test_pipeline_log_exists_and_correct():
    assert os.path.isfile(LOG_PATH), f"Log file missing at {LOG_PATH}"
    with open(LOG_PATH, "r") as f:
        lines = [line.strip() for line in f if line.strip()]
    assert len(lines) >= 3, "Log file does not contain enough lines"
    last_three = lines[-3:]
    assert last_three[0] == "[EXTRACT] records_read=8", f"Expected '[EXTRACT] records_read=8', got '{last_three[0]}'"
    assert last_three[1] == "[TRANSFORM] duplicates_dropped=3", f"Expected '[TRANSFORM] duplicates_dropped=3', got '{last_three[1]}'"
    assert last_three[2] == "[LOAD] records_written=5", f"Expected '[LOAD] records_written=5', got '{last_three[2]}'"


def test_output_file_exists_and_valid_jsonl():
    assert os.path.isfile(OUTPUT_PATH), f"Output file missing at {OUTPUT_PATH}"
    records = []
    with open(OUTPUT_PATH, "r") as f:
        for i, line in enumerate(f):
            line = line.strip()
            if not line:
                continue
            try:
                records.append(json.loads(line))
            except json.JSONDecodeError:
                pytest.fail(f"Line {i+1} in {OUTPUT_PATH} is not valid JSON: {line}")
    assert len(records) == 5, f"Expected exactly 5 records in output, found {len(records)}"
    required_fields = {"delivery_id", "user_id", "timestamp", "amount", "currency"}
    for i, record in enumerate(records):
        assert set(record.keys()) == required_fields, f"Record {i+1} missing or has extra fields: {record.keys()}"
        assert isinstance(record["amount"], float) or isinstance(record["amount"], int), f"Record {i+1} amount must be a number"


def test_output_records_correctness_and_sorting():
    assert os.path.isfile(OUTPUT_PATH), f"Output file missing at {OUTPUT_PATH}"
    records = []
    with open(OUTPUT_PATH, "r") as f:
        for line in f:
            line = line.strip()
            if line:
                records.append(json.loads(line))
    timestamps = [r["timestamp"] for r in records]
    assert timestamps == sorted(timestamps), "Records in output file are not sorted chronologically by timestamp"
    expected_records = [
        {"delivery_id": "d_1001", "user_id": "u_abc", "timestamp": "2023-10-01T10:00:00Z", "amount": 150.0, "currency": "USD"},
        {"delivery_id": "d_1002", "user_id": "u_xyz", "timestamp": "2023-10-01T10:05:00Z", "amount": 20.5, "currency": "EUR"},
        {"delivery_id": "d_2001", "user_id": "u_def", "timestamp": "2023-10-01T10:10:00Z", "amount": 99.99, "currency": "USD"},
        {"delivery_id": "d_2003", "user_id": "u_ghi", "timestamp": "2023-10-01T10:15:00Z", "amount": 50.0, "currency": "GBP"},
        {"delivery_id": "d_3002", "user_id": "u_jkl", "timestamp": "2023-10-01T10:20:00Z", "amount": 200.0, "currency": "JPY"}
    ]
    assert len(records) == len(expected_records), "Mismatch in number of output records"
    for i, (actual, expected) in enumerate(zip(records, expected_records)):
        assert actual["delivery_id"] == expected["delivery_id"], f"Record {i+1} delivery_id mismatch: {actual['delivery_id']} != {expected['delivery_id']}"
        assert actual["user_id"] == expected["user_id"], f"Record {i+1} user_id mismatch"
        assert actual["timestamp"] == expected["timestamp"], f"Record {i+1} timestamp mismatch"
        assert actual["currency"] == expected["currency"], f"Record {i+1} currency mismatch"
        assert float(actual["amount"]) == float(expected["amount"]), f"Record {i+1} amount mismatch: {actual['amount']} != {expected['amount']}"
TEST_EOF

python3 -m pytest /tmp/test_original_state.py -x --tb=short || fail

python3 << 'PY_EOF' || exit 1
import csv
import json
import os
import secrets
import xml.etree.ElementTree as ET

base = "/home/user/etl/input"
token = secrets.token_hex(8)

def rec(delivery, user, timestamp, amount, currency):
    return {
        "delivery_id": f"{delivery}_{token}",
        "user_id": f"{user}_{token}",
        "timestamp": timestamp,
        "amount": amount,
        "currency": currency,
    }

# Six logical transactions in deliberately non-chronological file order.
a = rec("csv_a", "user_a", "2026-04-03T10:30:00Z", "101.20", "USD")
b = rec("csv_b", "user_b", "2026-04-03T10:05:00Z", "22.50", "EUR")
c = rec("json_c", "user_c", "2026-04-03T10:20:00Z", 73.25, "GBP")
d = rec("json_d", "user_d", "2026-04-03T10:00:00Z", 40.5, "CAD")
e = rec("json_e", "user_e", "2026-04-03T10:40:00Z", 9.0, "AUD")
f = rec("xml_f", "user_f", "2026-04-03T10:10:00Z", "300.00", "JPY")

def duplicate(source, delivery, amount=None, currency=None):
    result = dict(source)
    result["delivery_id"] = f"{delivery}_{token}"
    if amount is not None:
        result["amount"] = amount
    if currency is not None:
        result["currency"] = currency
    return result

csv_records = [a, b, duplicate(a, "csv_a_retry", "101.2")]
json_records = [c, duplicate(b, "json_b_retry", 22.5, "ZZZ"), d, e]
xml_records = [duplicate(c, "xml_c_retry", "73.250"), f, duplicate(d, "xml_d_retry", "40.50")]

with open(os.path.join(base, "batch_a.csv"), "w", newline="") as fh:
    writer = csv.DictWriter(fh, fieldnames=["delivery_id", "user_id", "timestamp", "amount", "currency"])
    writer.writeheader()
    writer.writerows(csv_records)

with open(os.path.join(base, "batch_b.json"), "w") as fh:
    json.dump(json_records, fh)

root = ET.Element("transactions")
for record in xml_records:
    node = ET.SubElement(root, "transaction")
    for field in ["delivery_id", "user_id", "timestamp", "amount", "currency"]:
        ET.SubElement(node, field).text = str(record[field])
ET.ElementTree(root).write(os.path.join(base, "batch_c.xml"), encoding="unicode")
PY_EOF
[ $? -eq 0 ] || fail

INPUT_HASHES=$(sha256sum "$INPUT_DIR/batch_a.csv" "$INPUT_DIR/batch_b.json" "$INPUT_DIR/batch_c.xml") || fail
rm -f "$OUTPUT_PATH"
timeout 20s python3 "$SCRIPT" || fail
[ "$INPUT_HASHES" = "$(sha256sum "$INPUT_DIR/batch_a.csv" "$INPUT_DIR/batch_b.json" "$INPUT_DIR/batch_c.xml")" ] || fail

cat << 'TEST_EOF' > /tmp/test_dynamic_state.py
import csv
import hashlib
import json
import os
import xml.etree.ElementTree as ET

BASE = "/home/user/etl/input"
LOG_PATH = "/home/user/etl/pipeline.log"
OUTPUT_PATH = "/home/user/etl/output/clean_transactions.jsonl"
FIELDS = {"delivery_id", "user_id", "timestamp", "amount", "currency"}


def source_records():
    records = []
    with open(os.path.join(BASE, "batch_a.csv"), newline="") as fh:
        records.extend(dict(row) for row in csv.DictReader(fh))
    with open(os.path.join(BASE, "batch_b.json")) as fh:
        records.extend(json.load(fh))
    root = ET.parse(os.path.join(BASE, "batch_c.xml")).getroot()
    for node in root.findall("transaction"):
        records.append({field: node.findtext(field) for field in FIELDS})
    return records


def expected_records(records):
    seen = set()
    result = []
    for record in records:
        normalized_amount = f"{float(record['amount']):.2f}"
        material = f"{record['user_id']}|{record['timestamp']}|{normalized_amount}"
        fingerprint = hashlib.sha256(material.encode()).hexdigest()
        if fingerprint in seen:
            continue
        seen.add(fingerprint)
        result.append({
            "delivery_id": record["delivery_id"],
            "user_id": record["user_id"],
            "timestamp": record["timestamp"],
            "amount": float(record["amount"]),
            "currency": record["currency"],
        })
    return sorted(result, key=lambda r: r["timestamp"])


def test_dynamic_execution_result():
    inputs = source_records()
    expected = expected_records(inputs)
    assert os.path.isfile(OUTPUT_PATH), f"Output file missing at {OUTPUT_PATH}"
    actual = []
    with open(OUTPUT_PATH) as fh:
        for line_number, line in enumerate(fh, 1):
            line = line.strip()
            if not line:
                continue
            record = json.loads(line)
            assert set(record) == FIELDS, f"Record {line_number} has incorrect fields"
            assert isinstance(record["amount"], (int, float)) and not isinstance(record["amount"], bool)
            actual.append(record)
    assert [r["timestamp"] for r in actual] == sorted(r["timestamp"] for r in actual)
    assert actual == expected

    with open(LOG_PATH) as fh:
        lines = [line.strip() for line in fh if line.strip()]
    duplicates = len(inputs) - len(expected)
    assert len(lines) >= 3
    assert lines[-3:] == [
        f"[EXTRACT] records_read={len(inputs)}",
        f"[TRANSFORM] duplicates_dropped={duplicates}",
        f"[LOAD] records_written={len(expected)}",
    ]
TEST_EOF

if python3 -m pytest /tmp/test_dynamic_state.py -x --tb=short; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
