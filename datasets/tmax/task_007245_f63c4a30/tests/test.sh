#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import urllib.parse
import pytest

REPORT_PATH = '/home/user/incident_report.json'
LOG_PATH = '/home/user/traffic.log'

def get_expected_values():
    """Dynamically parse the log file to determine the expected values."""
    assert os.path.exists(LOG_PATH), f"Log file {LOG_PATH} is missing."

    attacker_ip = None
    compromised_password = None
    successful_lfi_payload = None

    with open(LOG_PATH, 'r') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue

            # Parse line: [Timestamp] IP_Address HTTP_Method URL Request_Body HTTP_Status
            # Timestamp has spaces, so split from the right or after the closing bracket.
            parts = line.split('] ', 1)
            if len(parts) != 2:
                continue

            # IP_Address HTTP_Method URL Request_Body HTTP_Status
            # Request_Body could be JSON with spaces, so we need to be careful.
            # We can split by spaces but limit splits, or extract from the right.
            # The HTTP_Status is the last token.
            tokens = parts[1].rsplit(' ', 1)
            if len(tokens) != 2:
                continue

            status = tokens[1]
            rest = tokens[0]

            # Now rest is: IP_Address HTTP_Method URL Request_Body
            # IP, Method, URL are single tokens without spaces.
            rest_tokens = rest.split(' ', 3)
            if len(rest_tokens) < 4:
                continue

            ip = rest_tokens[0]
            method = rest_tokens[1]
            url = rest_tokens[2]
            body = rest_tokens[3]

            if status == "200":
                if method == "POST" and url == "/api/login":
                    try:
                        payload = json.loads(body)
                        if payload.get("user") == "admin":
                            compromised_password = payload.get("pass")
                            attacker_ip = ip
                    except json.JSONDecodeError:
                        pass

                elif method == "GET" and "/api/data?file=" in url and "../" in url:
                    # Parse the URL to get the file parameter
                    parsed_url = urllib.parse.urlparse(url)
                    query_params = urllib.parse.parse_qs(parsed_url.query)
                    if 'file' in query_params:
                        successful_lfi_payload = query_params['file'][0]
                        # Verify this IP matches the attacker IP if already found
                        if attacker_ip is None:
                            attacker_ip = ip

    return attacker_ip, compromised_password, successful_lfi_payload

def test_incident_report_exists():
    assert os.path.exists(REPORT_PATH), f"The report file {REPORT_PATH} does not exist."
    assert os.path.isfile(REPORT_PATH), f"The path {REPORT_PATH} is not a file."

def test_incident_report_valid_json():
    with open(REPORT_PATH, 'r') as f:
        try:
            json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {REPORT_PATH} does not contain valid JSON.")

def test_incident_report_content():
    expected_ip, expected_pass, expected_lfi = get_expected_values()

    assert expected_ip is not None, "Could not determine attacker IP from log."
    assert expected_pass is not None, "Could not determine compromised password from log."
    assert expected_lfi is not None, "Could not determine successful LFI payload from log."

    with open(REPORT_PATH, 'r') as f:
        data = json.load(f)

    assert "attacker_ip" in data, "Key 'attacker_ip' is missing from the JSON report."
    assert "compromised_password" in data, "Key 'compromised_password' is missing from the JSON report."
    assert "successful_lfi_payload" in data, "Key 'successful_lfi_payload' is missing from the JSON report."

    assert data["attacker_ip"] == expected_ip, f"Expected attacker_ip to be '{expected_ip}', but got '{data['attacker_ip']}'."
    assert data["compromised_password"] == expected_pass, f"Expected compromised_password to be '{expected_pass}', but got '{data['compromised_password']}'."
    assert data["successful_lfi_payload"] == expected_lfi, f"Expected successful_lfi_payload to be '{expected_lfi}', but got '{data['successful_lfi_payload']}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
