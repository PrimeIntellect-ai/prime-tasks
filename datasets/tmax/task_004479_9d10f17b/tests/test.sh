#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import stat
import re

def test_query_template_extracted():
    report_file = "/home/user/pentest_target/report/query_template.txt"
    assert os.path.isfile(report_file), f"Expected file {report_file} does not exist."

    with open(report_file, "r") as f:
        content = f.read().strip()

    expected_query = "SELECT * FROM users WHERE username='%s' AND password='%s'"
    assert content == expected_query, f"Extracted query is incorrect. Expected: {expected_query}, Got: {content}"

def test_attacker_logs_redacted():
    log_file = "/home/user/pentest_target/logs/access.log"
    report_file = "/home/user/pentest_target/report/attacker_logs_redacted.txt"

    assert os.path.isfile(log_file), f"Original log file {log_file} is missing."
    assert os.path.isfile(report_file), f"Expected report file {report_file} does not exist."

    expected_access_log = """192.168.1.10 - - [10/Oct/2023:13:55:36 -0700] "GET /cgi-bin/process_login?user=alice&pass=secret&SessionID=9a8b7c6d HTTP/1.1" 200 1024
10.0.0.5 - - [10/Oct/2023:14:01:12 -0700] "GET /cgi-bin/process_login?user=admin'%20OR%20'1'%3D'1&pass=foo&SessionID=f4e3d2c1 HTTP/1.1" 200 2048
192.168.1.12 - - [10/Oct/2023:14:05:00 -0700] "GET /cgi-bin/process_login?user=bob&pass=1234&SessionID=11223344 HTTP/1.1" 401 512
172.16.0.4 - - [10/Oct/2023:14:10:05 -0700] "GET /cgi-bin/process_login?user=admin'%20OR%20'1'%3D'1&pass=bar&SessionID=x9y8z7w6 HTTP/1.1" 401 512
10.0.0.9 - - [10/Oct/2023:14:15:22 -0700] "GET /cgi-bin/process_login?user=admin'%20OR%20'1'%3D'1&pass=baz&SessionID=aabbccdd HTTP/1.1" 200 2048
"""
    with open(log_file, "r") as f:
        current_access_log = f.read()
    assert current_access_log == expected_access_log, "Original access.log was modified."

    # Derive expected redacted logs from the verified original access.log
    expected_lines = []
    with open(log_file, "r") as f:
        for line in f:
            if "admin'%20OR%20'1'%3D'1" in line and " 200 " in line:
                # Replace SessionID value with REDACTED
                redacted_line = re.sub(r"SessionID=[^&\s]+", "SessionID=REDACTED", line)
                expected_lines.append(redacted_line.strip())

    with open(report_file, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert len(actual_lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in redacted logs, got {len(actual_lines)}."

    for expected, actual in zip(expected_lines, actual_lines):
        assert expected == actual, f"Log line mismatch.\nExpected: {expected}\nGot:      {actual}"

def test_binary_permissions():
    binary_path = "/home/user/pentest_target/cgi-bin/process_login"
    assert os.path.isfile(binary_path), f"Binary {binary_path} does not exist."

    st = os.stat(binary_path)
    perms = stat.S_IMODE(st.st_mode)

    assert perms == 0o700, f"Permissions for {binary_path} are incorrect. Expected 700, got {oct(perms)[2:]}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
