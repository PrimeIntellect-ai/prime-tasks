#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import subprocess
import re
import pytest

REPORT_PATH = "/home/user/pentest_report.json"
BIN_PATH = "/home/user/malware_bypass.bin"
HASHER_PATH = "/home/user/custom_hasher.py"
RULES_PATH = "/home/user/rules.txt"
TRAFFIC_PATH = "/home/user/traffic.log"

EXPECTED_HASHER = b'''import sys

def compute_hash(data):
    h = 0
    for b in data:
        h = (h + b) % 65536
    return h

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python custom_hasher.py <file>")
        sys.exit(1)
    with open(sys.argv[1], 'rb') as f:
        print(compute_hash(f.read()))
'''

EXPECTED_RULES = b'''(?i)password=\\w+
UNION\\s+SELECT
admin_bypass
\\.\\./\\.\\./etc/passwd
'''

EXPECTED_TRAFFIC = b'''GET /index.html HTTP/1.1
POST /login HTTP/1.1 body: Password=SecretUser123
GET /images/logo.png HTTP/1.1
GET /api/data?query=UNION SELECT * FROM users HTTP/1.1
GET /about_us.html HTTP/1.1
POST /upload HTTP/1.1 body: admin_bypass=true
GET /api/v1/health HTTP/1.1
GET /styles.css HTTP/1.1
'''

def test_original_inputs_unchanged():
    for path, expected in (
        (HASHER_PATH, EXPECTED_HASHER),
        (RULES_PATH, EXPECTED_RULES),
        (TRAFFIC_PATH, EXPECTED_TRAFFIC),
    ):
        assert os.path.isfile(path), f"Required original file {path} is missing."
        assert not os.path.islink(path), f"Required original file {path} was replaced by a symlink."
        with open(path, 'rb') as f:
            actual = f.read()
        assert actual == expected, f"Required original file {path} was modified."

def test_report_exists_and_valid_json():
    assert os.path.isfile(REPORT_PATH), f"Report file {REPORT_PATH} does not exist."
    try:
        with open(REPORT_PATH, 'r') as f:
            json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"Report file {REPORT_PATH} is not valid JSON.")

def test_report_cwe_id():
    with open(REPORT_PATH, 'r') as f:
        data = json.load(f)

    assert "cwe_id" in data, "JSON report missing 'cwe_id' key."
    assert data["cwe_id"] == "CWE-327", f"Incorrect CWE ID. Expected 'CWE-327', got '{data['cwe_id']}'."

def test_report_flagged_log_lines():
    with open(REPORT_PATH, 'r') as f:
        data = json.load(f)

    assert "flagged_log_lines" in data, "JSON report missing 'flagged_log_lines' key."

    assert os.path.isfile(RULES_PATH), f"Rules file {RULES_PATH} missing."
    assert os.path.isfile(TRAFFIC_PATH), f"Traffic log {TRAFFIC_PATH} missing."

    with open(RULES_PATH, 'r') as f:
        rules = [line.strip() for line in f if line.strip()]

    with open(TRAFFIC_PATH, 'r') as f:
        traffic_lines = f.read().splitlines()

    expected_matches = []
    for i, line in enumerate(traffic_lines, start=1):
        for rule in rules:
            if re.search(rule, line):
                expected_matches.append(i)
                break

    assert data["flagged_log_lines"] == expected_matches, f"Incorrect flagged log lines. Expected {expected_matches}, got {data['flagged_log_lines']}."

def test_malware_bypass_bin_exists_and_size():
    assert os.path.isfile(BIN_PATH), f"Collision file {BIN_PATH} does not exist."
    size = os.path.getsize(BIN_PATH)
    assert size >= 10, f"Collision file {BIN_PATH} is too small. Expected at least 10 bytes, got {size} bytes."

def test_malware_bypass_bin_hash_collision():
    assert os.path.isfile(HASHER_PATH), f"Hasher script {HASHER_PATH} is missing."
    assert os.path.isfile(BIN_PATH), f"Collision file {BIN_PATH} is missing."

    with open(BIN_PATH, 'rb') as f:
        collision_data = f.read()
    independent_hash = sum(collision_data) % 65536
    assert independent_hash == 4919, f"Collision file independently hashes to {independent_hash}, not 4919."

    try:
        out = subprocess.check_output(['python3', HASHER_PATH, BIN_PATH], stderr=subprocess.STDOUT)
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Running custom_hasher.py failed with error: {e.output.decode('utf-8', errors='ignore')}")

    output_str = out.decode('utf-8', errors='ignore').strip()
    assert output_str == "4919", f"Hash output did not match target 4919. Got: '{output_str}'"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
