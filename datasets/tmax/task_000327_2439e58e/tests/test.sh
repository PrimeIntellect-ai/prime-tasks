#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import json
import os
import re
import subprocess
import tempfile
from datetime import datetime

import jwt
import pytest

REPORT_PATH = "/home/user/investigation/report.json"
ELF_PATH = "/home/user/investigation/suspicious.elf"
LOG_PATH = "/home/user/investigation/access.log"


def derive_expected_report():
    """Independently extract the secret and derive valid entries from the supplied artifacts."""
    with tempfile.TemporaryDirectory() as tmpdir:
        payload_path = os.path.join(tmpdir, "hidden_payload.bin")
        copied_elf = os.path.join(tmpdir, "suspicious-copy.elf")
        subprocess.run(
            [
                "objcopy",
                "--dump-section",
                f".hidden_payload={payload_path}",
                ELF_PATH,
                copied_elf,
            ],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        with open(payload_path, "rb") as f:
            encoded_payload = f.read()

    xored_payload = base64.b64decode(encoded_payload, validate=True)
    secret = bytes(byte ^ 0x5A for byte in xored_payload).decode("utf-8")

    line_re = re.compile(
        r'^(?P<ip>\d{1,3}(?:\.\d{1,3}){3})\s+\S+\s+\S+\s+'
        r'\[(?P<timestamp>[^\]]+)\]\s+'
        r'"\S+\s+(?P<endpoint>\S+)\s+HTTP/[^\"]+"'
    )
    token_re = re.compile(r'\bBearer\s+(?P<token>[A-Za-z0-9._-]+)')
    expected = []

    with open(LOG_PATH, "r", encoding="utf-8") as f:
        for line in f:
            line_match = line_re.search(line)
            token_match = token_re.search(line)
            if not line_match or not token_match:
                continue

            try:
                jwt.decode(token_match.group("token"), secret, algorithms=["HS256"])
            except jwt.InvalidTokenError:
                continue

            timestamp = datetime.strptime(
                line_match.group("timestamp"), "%d/%b/%Y:%H:%M:%S %z"
            ).strftime("%Y-%m-%dT%H:%M:%S")
            ip_parts = line_match.group("ip").split(".")
            expected.append(
                {
                    "timestamp": timestamp,
                    "endpoint": line_match.group("endpoint"),
                    "redacted_ip": ".".join(ip_parts[:3] + ["XXX"]),
                }
            )

    return expected


def test_report_exists():
    """Test that the final report.json file has been created."""
    assert os.path.isfile(REPORT_PATH), f"Report file {REPORT_PATH} does not exist. Did you save your output?"


def test_report_is_valid_json():
    """Test that the report.json file contains valid JSON."""
    with open(REPORT_PATH, "r") as f:
        try:
            json.load(f)
        except json.JSONDecodeError as e:
            pytest.fail(f"The file {REPORT_PATH} does not contain valid JSON: {e}")


def test_report_content_and_structure():
    """Test that the report contains the correct redacted IPs and endpoints for valid JWTs."""
    with open(REPORT_PATH, "r") as f:
        data = json.load(f)

    assert isinstance(data, list), f"Expected the root of the JSON to be an array, but got {type(data).__name__}."
    assert len(data) == 2, f"Expected exactly 2 valid JWT entries in the report, but found {len(data)}."

    entry1 = data[0]
    assert "timestamp" in entry1, "First entry is missing the 'timestamp' key."
    assert entry1["timestamp"] == "2023-10-25T14:32:01", f"First entry timestamp is incorrect. Got: {entry1.get('timestamp')}"
    assert entry1.get("endpoint") == "/api/v1/admin/dump", f"First entry endpoint is incorrect. Got: {entry1.get('endpoint')}"
    assert entry1.get("redacted_ip") == "10.4.5.XXX", f"First entry redacted_ip is incorrect. Got: {entry1.get('redacted_ip')}"

    entry2 = data[1]
    assert "timestamp" in entry2, "Second entry is missing the 'timestamp' key."
    assert entry2["timestamp"] == "2023-10-25T14:40:22", f"Second entry timestamp is incorrect. Got: {entry2.get('timestamp')}"
    assert entry2.get("endpoint") == "/api/v1/system/keys", f"Second entry endpoint is incorrect. Got: {entry2.get('endpoint')}"
    assert entry2.get("redacted_ip") == "8.8.8.XXX", f"Second entry redacted_ip is incorrect. Got: {entry2.get('redacted_ip')}"


def test_report_exactly_matches_artifacts():
    """Require all fields and ordering to match independently decoded and validated artifacts."""
    with open(REPORT_PATH, "r", encoding="utf-8") as f:
        actual = json.load(f)
    expected = derive_expected_report()
    assert actual == expected, f"Report does not match the valid JWT requests derived from the ELF and log. Expected: {expected!r}; got: {actual!r}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
