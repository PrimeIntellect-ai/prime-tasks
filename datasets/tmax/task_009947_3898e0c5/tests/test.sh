#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os

def test_backup_logs_tail():
    log_out_path = "/home/user/backup_logs_tail.txt"
    assert os.path.isfile(log_out_path), f"File {log_out_path} is missing."

    expected_content = """=== app_backup.zip::nested/error.log ===
Warning: High memory usage
Error: Timeout on port 8080
Fatal: Process crashed
=== db/sync.log ===
Records: 1042
Sync complete
Connection closed
=== web/archived/old_logs.tar.gz::access.log ===
GET /app.js 200
POST /api/login 401
POST /api/login 200"""

    with open(log_out_path, "r", encoding="utf-8") as f:
        actual_content = f.read().strip()

    assert actual_content == expected_content, f"Content of {log_out_path} does not match expected output.\nExpected:\n{expected_content}\n\nActual:\n{actual_content}"

def test_backup_bin_manifest():
    bin_out_path = "/home/user/backup_bin_manifest.txt"
    assert os.path.isfile(bin_out_path), f"File {bin_out_path} is missing."

    expected_content = """41b2e65d2b1f14421b920cc211326442cce4a3dbbc08794c4ec0cf47690b2bd2  db/state.bin
d0e8cb55dc03f39cf9e0be628fb60afbe06cdbda3ed8bdbaefcfd0da5f0d36c2  web/archived/old_logs.tar.gz::core.bin"""

    with open(bin_out_path, "r", encoding="utf-8") as f:
        actual_content = f.read().strip()

    assert actual_content == expected_content, f"Content of {bin_out_path} does not match expected output.\nExpected:\n{expected_content}\n\nActual:\n{actual_content}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
