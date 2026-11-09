#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json

def test_evidence_report_exists():
    path = "/home/user/evidence_report.json"
    assert os.path.isfile(path), f"File {path} does not exist. The report was not created."

def test_evidence_report_contents():
    path = "/home/user/evidence_report.json"
    assert os.path.isfile(path), f"File {path} does not exist."

    with open(path, 'r') as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            assert False, f"File {path} is not valid JSON."

    expected_token = "C2-AUTH-99A8-XYZ2"
    expected_flag = "FLAG{ev1d3nc3_r3c0v3r3d}"
    expected_domains = ["bank.local", "secure-vault.net"]

    assert "c2_token" in report, "The key 'c2_token' is missing from the report."
    assert report["c2_token"] == expected_token, f"Expected c2_token '{expected_token}', but got '{report['c2_token']}'."

    assert "secret_flag" in report, "The key 'secret_flag' is missing from the report."
    assert report["secret_flag"] == expected_flag, f"Expected secret_flag '{expected_flag}', but got '{report['secret_flag']}'."

    assert "compromised_domains" in report, "The key 'compromised_domains' is missing from the report."
    assert isinstance(report["compromised_domains"], list), "'compromised_domains' should be a list."

    # The instructions specify alphabetical sorting
    assert report["compromised_domains"] == expected_domains, f"Expected compromised_domains {expected_domains}, but got {report['compromised_domains']}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
