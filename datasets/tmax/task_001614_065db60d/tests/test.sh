#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import re

TRAFFIC_PATH = "/home/user/traffic_dump.json"
REPORT_PATH = "/home/user/investigation.txt"
PAYLOAD_PATH = "/home/user/payload.bin"
SALT = "SuperSecretSalt2024"


def expected_artifacts():
    with open(TRAFFIC_PATH, "r", encoding="utf-8") as f:
        requests = json.load(f)

    malicious = []
    for request in requests:
        headers = request["headers"]
        expected_token = hashlib.md5(
            (headers["User-Agent"] + SALT).encode("utf-8")
        ).hexdigest()
        if headers["X-Admin-Token"] != expected_token:
            malicious.append(request)

    assert len(malicious) == 1, "Traffic dump must contain exactly one invalid admin token"
    request = malicious[0]
    body = request["body"]
    start_marker = "ELF_START:"
    end_marker = ":ELF_END"
    assert body.count(start_marker) == 1 and body.count(end_marker) == 1
    hex_payload = body.split(start_marker, 1)[1].split(end_marker, 1)[0]
    expected_payload = bytes.fromhex(hex_payload)

    c2_matches = re.findall(rb"C2_IP=((?:[0-9]{1,3}\.){3}[0-9]{1,3})", expected_payload)
    assert len(c2_matches) == 1, "Expected exactly one C2_IP string in extracted ELF"
    c2_ip = c2_matches[0].decode("ascii")
    assert all(0 <= int(part) <= 255 for part in c2_ip.split("."))

    source_ip = request["headers"]["X-Forwarded-For"]
    forged_token = request["headers"]["X-Admin-Token"]
    expected_report = (
        f"Malicious Source IP: {source_ip}\n"
        f"Forged Token: {forged_token}\n"
        f"C2 Server: {c2_ip}\n"
    )
    return expected_payload, expected_report, source_ip, forged_token, c2_ip


def test_investigation_file_exists():
    assert os.path.isfile(REPORT_PATH), f"Expected investigation report not found at {REPORT_PATH}"


def test_investigation_file_contents():
    _, expected_report, source_ip, forged_token, c2_ip = expected_artifacts()
    with open(REPORT_PATH, "r", encoding="utf-8") as f:
        content = f.read()

    expected_ip = f"Malicious Source IP: {source_ip}"
    expected_token = f"Forged Token: {forged_token}"
    expected_c2 = f"C2 Server: {c2_ip}"
    assert expected_ip in content, f"Missing or incorrect Malicious Source IP in {REPORT_PATH}"
    assert expected_token in content, f"Missing or incorrect Forged Token in {REPORT_PATH}"
    assert expected_c2 in content, f"Missing or incorrect C2 Server in {REPORT_PATH}"
    assert content == expected_report, f"Investigation report at {REPORT_PATH} is not in the exact required format"


def test_payload_bin_exists():
    assert os.path.isfile(PAYLOAD_PATH), f"Expected extracted binary not found at {PAYLOAD_PATH}"


def test_payload_bin_is_elf():
    with open(PAYLOAD_PATH, "rb") as f:
        payload = f.read()
    assert payload[:4] == b"\x7fELF", f"File at {PAYLOAD_PATH} does not appear to be a valid ELF binary (incorrect magic bytes)."


def test_payload_bin_is_extracted_payload():
    expected_payload, _, _, _, _ = expected_artifacts()
    with open(PAYLOAD_PATH, "rb") as f:
        actual_payload = f.read()
    assert actual_payload == expected_payload, f"File at {PAYLOAD_PATH} is not the payload embedded in the malicious request"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
