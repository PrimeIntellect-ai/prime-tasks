#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess

BUG_REPORT_PATH = "/home/user/bug_report.txt"
REPO_PATH = "/home/user/data_processor"
EXPECTED_VAR = "quarantine_record_cache"

def test_bug_report_exists():
    assert os.path.isfile(BUG_REPORT_PATH), f"Bug report file not found at {BUG_REPORT_PATH}"

def test_bug_report_format_and_content():
    assert os.path.isfile(BUG_REPORT_PATH), f"Bug report file not found at {BUG_REPORT_PATH}"

    expected_commit_hash = subprocess.check_output(
        [
            "git", "-C", REPO_PATH, "log", "--reverse", "--format=%H",
            "-S", f"{EXPECTED_VAR} = []", "--", "processor.py"
        ],
        text=True,
    ).splitlines()[0].strip()

    with open(BUG_REPORT_PATH, "r") as f:
        content = f.read()

    commit_match = re.search(r"^COMMIT_HASH:\s*([a-f0-9]{40})$", content, re.MULTILINE)
    assert commit_match is not None, "Could not find a valid COMMIT_HASH line with a 40-character hash in the bug report."
    actual_commit_hash = commit_match.group(1)

    var_match = re.search(r"^LEAKING_VAR:\s*(\w+)$", content, re.MULTILINE)
    assert var_match is not None, "Could not find a valid LEAKING_VAR line in the bug report."
    actual_var = var_match.group(1)

    assert actual_commit_hash == expected_commit_hash, f"Expected COMMIT_HASH to be {expected_commit_hash}, but got {actual_commit_hash}"
    assert actual_var == EXPECTED_VAR, f"Expected LEAKING_VAR to be '{EXPECTED_VAR}', but got '{actual_var}'"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
