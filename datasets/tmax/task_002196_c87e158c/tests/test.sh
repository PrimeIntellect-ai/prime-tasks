#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import hashlib
import stat

def test_security_report_exists_and_correct():
    report_path = "/home/user/security_report.txt"
    log_path = "/home/user/uploads_log.txt"
    base_dir = "/home/user/app/uploads/"

    assert os.path.isfile(report_path), f"Report file {report_path} does not exist or is not a file."
    assert os.path.isfile(log_path), f"Log file {log_path} does not exist."

    # Parse log file to find traversal
    traversal_filename = None
    expected_hash_from_log = None
    with open(log_path, 'r') as f:
        for line in f:
            if '../' in line:
                parts = [p.strip() for p in line.split('|')]
                if len(parts) >= 5:
                    traversal_filename = parts[3]
                    expected_hash_from_log = parts[4]
                    break

    assert traversal_filename is not None, "Could not find path traversal entry (containing '../') in the log file."

    # Compute expected absolute path
    expected_abs_path = os.path.abspath(os.path.join(base_dir, traversal_filename))

    # Compute actual hash of the file
    assert os.path.isfile(expected_abs_path), f"Malicious file {expected_abs_path} does not exist on disk."

    sha256 = hashlib.sha256()
    with open(expected_abs_path, 'rb') as f:
        sha256.update(f.read())
    actual_hash = sha256.hexdigest()

    hash_match = "Yes" if actual_hash == expected_hash_from_log else "No"

    # Get permissions
    st = os.stat(expected_abs_path)
    perms = stat.S_IMODE(st.st_mode)
    perms_str = f"{perms:04o}"

    # Read the report
    with open(report_path, 'r') as f:
        report_content = [line.strip() for line in f.read().strip().splitlines() if line.strip()]

    assert len(report_content) == 3, f"Report should have exactly 3 lines of findings, found {len(report_content)}."

    expected_line1 = f"Malicious File: {expected_abs_path}"
    expected_line2 = f"Hash Match: {hash_match}"
    expected_line3 = f"Permissions: {perms_str}"

    assert report_content[0] == expected_line1, f"First line incorrect. Expected '{expected_line1}', got '{report_content[0]}'"
    assert report_content[1] == expected_line2, f"Second line incorrect. Expected '{expected_line2}', got '{report_content[1]}'"
    assert report_content[2] == expected_line3, f"Third line incorrect. Expected '{expected_line3}', got '{report_content[2]}'"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
