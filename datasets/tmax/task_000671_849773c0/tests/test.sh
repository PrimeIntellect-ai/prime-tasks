#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest
from decimal import Decimal, getcontext

REPORT_PATH = "/home/user/analysis_report.json"

def get_expected_key():
    getcontext().prec = 50
    # The salt length is 21 ("sUp3r_s3cr3t_s4lt_99!")
    x = Decimal('0.21')
    r = Decimal('3.99')

    for _ in range(100):
        x = r * x * (Decimal('1') - x)

    return str(x)

def test_analysis_report_exists():
    assert os.path.isfile(REPORT_PATH), f"The analysis report at '{REPORT_PATH}' does not exist."

def test_analysis_report_contents():
    with open(REPORT_PATH, 'r') as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file '{REPORT_PATH}' does not contain valid JSON.")

    expected_salt = "sUp3r_s3cr3t_s4lt_99!"
    expected_email = "ceo@megacorp.local"
    expected_key = get_expected_key()

    assert "recovered_salt" in report, "Missing 'recovered_salt' key in the report."
    assert report["recovered_salt"] == expected_salt, f"Incorrect recovered_salt. Expected '{expected_salt}', got '{report['recovered_salt']}'."

    assert "target_email" in report, "Missing 'target_email' key in the report."
    assert report["target_email"] == expected_email, f"Incorrect target_email. Expected '{expected_email}', got '{report['target_email']}'."

    assert "precise_key" in report, "Missing 'precise_key' key in the report."
    assert report["precise_key"] == expected_key, f"Incorrect precise_key. Expected '{expected_key}', got '{report['precise_key']}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
