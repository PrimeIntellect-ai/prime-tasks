#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import re
import subprocess

ORIGINAL_PATH = "/home/user/investigation/http_logs.json"
REDACTED_PATH = "/home/user/investigation/http_logs_redacted.json"
SCRIPT_PATH = "/home/user/redact.py"
SUMMARY_PATH = "/home/user/forensic_summary.json"
SSN_PATTERN = re.compile(r"\d{3}-\d{2}-\d{4}")


def test_redaction_script_exists_and_runs():
    assert os.path.isfile(SCRIPT_PATH), f"Redaction script missing: {SCRIPT_PATH}"
    result = subprocess.run(
        ["python3", SCRIPT_PATH],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"{SCRIPT_PATH} failed with exit code {result.returncode}:\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def test_redacted_logs_exist_and_valid():
    assert os.path.isfile(REDACTED_PATH), f"Redacted logs file missing: {REDACTED_PATH}"
    with open(REDACTED_PATH, "r") as f:
        try:
            redacted_logs = json.load(f)
        except json.JSONDecodeError:
            assert False, f"{REDACTED_PATH} is not valid JSON"
    assert isinstance(redacted_logs, list), "Redacted HTTP logs should be a JSON list"


def test_redacted_logs_content():
    with open(ORIGINAL_PATH, "r") as f:
        original_logs = json.load(f)
    with open(REDACTED_PATH, "r") as f:
        redacted_logs = json.load(f)

    assert len(original_logs) == len(redacted_logs), "Redacted logs must have the same number of entries as the original."

    for orig, red in zip(original_logs, redacted_logs):
        assert set(orig.keys()) == set(red.keys()), "Redacted logs must have identical structure to original logs."

        for key in ["timestamp", "source_ip", "method", "path"]:
            assert orig.get(key) == red.get(key), f"Field '{key}' was altered incorrectly."

        orig_headers = orig.get("headers", {})
        red_headers = red.get("headers", {})
        assert set(orig_headers.keys()) == set(red_headers.keys()), "Headers keys must remain identical."
        for hk, hv in orig_headers.items():
            expected_val = SSN_PATTERN.sub("XXX-XX-XXXX", hv)
            assert red_headers[hk] == expected_val, f"Header '{hk}' was not redacted correctly."

        orig_cookies = orig.get("cookies", {})
        red_cookies = red.get("cookies", {})
        assert set(orig_cookies.keys()) == set(red_cookies.keys()), "Cookies keys must remain identical."
        for ck, cv in orig_cookies.items():
            expected_val = SSN_PATTERN.sub("XXX-XX-XXXX", cv)
            assert red_cookies[ck] == expected_val, f"Cookie '{ck}' was not redacted correctly."


def test_forensic_summary_exists_and_valid():
    assert os.path.isfile(SUMMARY_PATH), f"Forensic summary file missing: {SUMMARY_PATH}"
    with open(SUMMARY_PATH, "r") as f:
        try:
            summary = json.load(f)
        except json.JSONDecodeError:
            assert False, f"{SUMMARY_PATH} is not valid JSON"
    assert isinstance(summary, dict), "Forensic summary should be a JSON object (dictionary)"


def test_forensic_summary_content():
    with open(SUMMARY_PATH, "r") as f:
        summary = json.load(f)

    expected_keys = {"privesc_vector", "malicious_ip", "exfiltrated_records_count"}
    assert set(summary.keys()) == expected_keys, f"Forensic summary must contain exactly these keys: {expected_keys}"
    assert summary["privesc_vector"] == "/home/user/investigation/system_dump/opt/maintenance/cleanup.sh", \
        "Incorrect privesc_vector in forensic summary."
    assert summary["malicious_ip"] == "203.0.113.88", \
        "Incorrect malicious_ip in forensic summary."
    assert summary["exfiltrated_records_count"] == 2, \
        "Incorrect exfiltrated_records_count in forensic summary."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
