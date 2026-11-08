#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import csv
import hashlib
from itertools import combinations

RAW_LOGS_PATH = "/home/user/raw_logs.jsonl"
OUTPUT_DIR = "/home/user/output"
INVALID_LOGS_PATH = os.path.join(OUTPUT_DIR, "invalid.jsonl")
MASKED_LOGS_PATH = os.path.join(OUTPUT_DIR, "masked_logs.jsonl")
SUMMARY_CSV_PATH = os.path.join(OUTPUT_DIR, "summary.csv")
ANOMALIES_JSON_PATH = os.path.join(OUTPUT_DIR, "anomalies.json")

def is_valid_log(entry):
    expected_fields = {"timestamp", "ip_address", "user_email", "endpoint", "status"}
    if set(entry.keys()) != expected_fields:
        return False
    if not isinstance(entry["timestamp"], str): return False
    if not isinstance(entry["ip_address"], str): return False
    if not isinstance(entry["user_email"], str): return False
    if not isinstance(entry["endpoint"], str): return False
    if not isinstance(entry["status"], int): return False
    if isinstance(entry["status"], bool): return False # bool is subclass of int in python
    return True

def mask_ip(ip):
    parts = ip.split(".")
    if len(parts) == 4:
        parts[-1] = "0"
        return ".".join(parts)
    return ip

def hash_email(email):
    return hashlib.sha256(email.encode('utf-8')).hexdigest()

def get_truth_data():
    with open(RAW_LOGS_PATH, "r") as f:
        raw_lines = f.read().splitlines()

    invalid_lines = []
    valid_entries = []

    for line in raw_lines:
        if not line.strip():
            continue
        try:
            entry = json.loads(line)
        except:
            invalid_lines.append(line)
            continue

        if is_valid_log(entry):
            valid_entries.append(entry)
        else:
            invalid_lines.append(line)

    masked_entries = []
    for entry in valid_entries:
        masked = entry.copy()
        masked["ip_address"] = mask_ip(entry["ip_address"])
        masked["user_email"] = hash_email(entry["user_email"])
        masked_entries.append(masked)

    ip_counts = {}
    for entry in masked_entries:
        ip = entry["ip_address"]
        ip_counts[ip] = ip_counts.get(ip, 0) + 1

    sorted_summary = sorted(ip_counts.items(), key=lambda x: (-x[1], x[0]))

    user_endpoints = {}
    for entry in masked_entries:
        user = entry["user_email"]
        ep = entry["endpoint"]
        if user not in user_endpoints:
            user_endpoints[user] = set()
        user_endpoints[user].add(ep)

    users = [u for u, eps in user_endpoints.items() if len(eps) > 0]
    best_pair = None
    best_sim = -1.0

    for u1, u2 in combinations(users, 2):
        s1 = user_endpoints[u1]
        s2 = user_endpoints[u2]
        intersection = len(s1.intersection(s2))
        union = len(s1.union(s2))
        sim = intersection / union if union > 0 else 0

        pair = tuple(sorted([u1, u2]))

        if sim > best_sim:
            best_sim = sim
            best_pair = pair
        elif sim == best_sim:
            if best_pair is None or pair < best_pair:
                best_sim = sim
                best_pair = pair

    anomaly_result = None
    if best_pair:
        anomaly_result = {
            "user1": best_pair[0],
            "user2": best_pair[1],
            "similarity": round(best_sim, 4)
        }

    return invalid_lines, masked_entries, sorted_summary, anomaly_result

def test_output_directory_exists():
    assert os.path.exists(OUTPUT_DIR), f"Output directory {OUTPUT_DIR} was not created."
    assert os.path.isdir(OUTPUT_DIR), f"{OUTPUT_DIR} is not a directory."

def test_invalid_logs():
    assert os.path.exists(INVALID_LOGS_PATH), f"Missing {INVALID_LOGS_PATH}"
    truth_invalid, _, _, _ = get_truth_data()

    with open(INVALID_LOGS_PATH, "r") as f:
        student_invalid = [line.strip() for line in f if line.strip()]

    assert len(student_invalid) == len(truth_invalid), f"Expected {len(truth_invalid)} invalid logs, found {len(student_invalid)}."

    # Check that exact strings match (order might not be strictly guaranteed if they processed differently, but usually is)
    assert sorted(student_invalid) == sorted([line.strip() for line in truth_invalid]), "Invalid logs content does not match the expected raw JSON strings."

def test_masked_logs():
    assert os.path.exists(MASKED_LOGS_PATH), f"Missing {MASKED_LOGS_PATH}"
    _, truth_masked, _, _ = get_truth_data()

    with open(MASKED_LOGS_PATH, "r") as f:
        student_masked = [json.loads(line) for line in f if line.strip()]

    assert len(student_masked) == len(truth_masked), f"Expected {len(truth_masked)} masked logs, found {len(student_masked)}."

    # We compare the list of dicts. Order should match if they processed sequentially.
    # If not, we can sort by timestamp.
    student_sorted = sorted(student_masked, key=lambda x: x["timestamp"])
    truth_sorted = sorted(truth_masked, key=lambda x: x["timestamp"])

    assert student_sorted == truth_sorted, "Masked logs do not match the expected masked and hashed data."

def test_summary_csv():
    assert os.path.exists(SUMMARY_CSV_PATH), f"Missing {SUMMARY_CSV_PATH}"
    _, _, truth_summary, _ = get_truth_data()

    with open(SUMMARY_CSV_PATH, "r", newline="") as f:
        reader = list(csv.reader(f))

    assert len(reader) > 0, "Summary CSV is empty."
    headers = reader[0]
    assert headers == ["ip_address", "request_count"], f"Expected headers ['ip_address', 'request_count'], got {headers}"

    student_data = []
    for row in reader[1:]:
        assert len(row) == 2, f"Invalid CSV row: {row}"
        student_data.append((row[0], int(row[1])))

    assert student_data == truth_summary, f"Summary CSV data or sorting is incorrect. Expected {truth_summary}, got {student_data}"

def test_anomalies_json():
    assert os.path.exists(ANOMALIES_JSON_PATH), f"Missing {ANOMALIES_JSON_PATH}"
    _, _, _, truth_anomaly = get_truth_data()

    with open(ANOMALIES_JSON_PATH, "r") as f:
        student_anomaly = json.load(f)

    assert student_anomaly == truth_anomaly, f"Anomalies JSON is incorrect. Expected {truth_anomaly}, got {student_anomaly}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
