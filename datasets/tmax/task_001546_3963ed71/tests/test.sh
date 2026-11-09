#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import re
import pytest

def get_expected_values():
    mem_dump_path = "/home/user/investigation/mem_dump.bin"
    domain = None
    if os.path.isfile(mem_dump_path):
        with open(mem_dump_path, "rb") as f:
            data = f.read()
        match = re.search(rb'([a-zA-Z0-9.-]+\.malware\.local)', data)
        if match:
            domain = match.group(1).decode('utf-8')

    logs = []
    for log_file in ["api.log", "db.log"]:
        path = f"/home/user/investigation/logs/{log_file}"
        if os.path.isfile(path):
            with open(path, "r") as f:
                for line in f:
                    line = line.strip()
                    if line:
                        parts = line.split(" ", 2)
                        if len(parts) >= 3:
                            logs.append((parts[0], parts[1], parts[2]))

    logs.sort(key=lambda x: x[0])

    missing_env = None
    last_event = None

    for i, log in enumerate(logs):
        if "EnvironmentError:" in log[2]:
            m = re.search(r'EnvironmentError:\s+(\w+)\s+not set', log[2])
            if m:
                missing_env = m.group(1)
        if log[1] == "CRITICAL" and "CRASH" in log[2]:
            if i > 0:
                last_event = logs[i-1][2]

    return domain, missing_env, last_event

def test_report_exists():
    assert os.path.isfile("/home/user/report.json"), "The report.json file was not found at /home/user/report.json."

def test_report_contents():
    expected_domain, expected_env, expected_last_event = get_expected_values()

    assert expected_domain is not None, "Could not derive the expected domain from mem_dump.bin"
    assert expected_env is not None, "Could not derive the missing environment variable from logs"
    assert expected_last_event is not None, "Could not derive the last event before crash from logs"

    with open("/home/user/report.json", "r") as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("report.json is not a valid JSON file.")

    assert "suspicious_domain" in report, "Key 'suspicious_domain' missing in report.json."
    assert report["suspicious_domain"] == expected_domain, f"Expected suspicious_domain to be '{expected_domain}', got '{report['suspicious_domain']}'."

    assert "missing_env_var" in report, "Key 'missing_env_var' missing in report.json."
    assert report["missing_env_var"] == expected_env, f"Expected missing_env_var to be '{expected_env}', got '{report['missing_env_var']}'."

    assert "last_event_before_crash" in report, "Key 'last_event_before_crash' missing in report.json."
    assert report["last_event_before_crash"] == expected_last_event, f"Expected last_event_before_crash to be '{expected_last_event}', got '{report['last_event_before_crash']}'."
TEST_EOF

if [ -f /home/user/investigate.py ] \
    && rm -f /home/user/report.json \
    && (cd /home/user && timeout 30s python3 /home/user/investigate.py) \
    && python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
