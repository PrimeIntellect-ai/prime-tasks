#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import re
from collections import Counter


def test_audit_report_exists_and_correct():
    report_path = "/home/user/audit_report.txt"
    auth_log_path = "/home/user/auth.log"
    webroot_path = "/home/user/webroot"

    assert os.path.isfile(report_path), f"Audit report file {report_path} is missing."

    # Preserve the original checks against the current source paths.
    assert os.path.isfile(auth_log_path), f"Log file {auth_log_path} is missing."
    ip_counter = Counter()
    ip_pattern = re.compile(r"Failed password.*from\s+([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)")

    with open(auth_log_path, "r") as f:
        for line in f:
            match = ip_pattern.search(line)
            if match:
                ip_counter[match.group(1)] += 1

    assert ip_counter, "No failed password attempts found in auth.log"
    expected_ip = ip_counter.most_common(1)[0][0]

    assert os.path.isdir(webroot_path), f"Webroot directory {webroot_path} is missing."
    world_writable_files = []
    for root, dirs, files in os.walk(webroot_path):
        for file in files:
            file_path = os.path.join(root, file)
            st = os.stat(file_path)
            if bool(st.st_mode & stat.S_IWOTH):
                world_writable_files.append(file_path)
    world_writable_files.sort()

    with open(report_path, "r") as f:
        actual_content = f.read()

    dynamic_expected_lines = [expected_ip] + world_writable_files
    actual_nonblank_lines = [line for line in actual_content.splitlines() if line.strip()]
    assert actual_nonblank_lines == dynamic_expected_lines, (
        f"Content of {report_path} does not match the supplied inputs.\n"
        f"Expected:\n{chr(10).join(dynamic_expected_lines)}\n\n"
        f"Got:\n{chr(10).join(actual_nonblank_lines)}"
    )

    # Expectations are anchored to the original fixtures, not agent-writable inputs.
    fixture_expected_lines = [
        "192.168.1.50",
        "/home/user/webroot/config.php",
        "/home/user/webroot/uploads/backdoor.php",
    ]
    assert actual_content in (
        "\n".join(fixture_expected_lines),
        "\n".join(fixture_expected_lines) + "\n",
    ), (
        f"Content of {report_path} is incorrect or contains extra text/blank lines.\n"
        f"Expected:\n{chr(10).join(fixture_expected_lines)}\n\n"
        f"Got:\n{actual_content}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
