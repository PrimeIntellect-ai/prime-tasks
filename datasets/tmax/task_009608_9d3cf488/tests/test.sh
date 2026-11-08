#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_script_exists():
    script_path = '/home/user/storage_monitor.py'
    assert os.path.isfile(script_path), f"The script {script_path} does not exist."

def test_alerts_log_exists_and_contents():
    log_path = '/home/user/alerts.log'
    assert os.path.isfile(log_path), f"The log file {log_path} was not created."

    with open(log_path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_alert = "[ALERT] Mountpoint /home/user/data/app exceeded quota. Current: 6000 bytes, Limit: 5000 bytes."
    expected_app_warn_1 = "[WARN] Mountpoint /home/user/data/app contains world-writable file: /home/user/data/app/file1.txt"
    expected_app_warn_2 = "[WARN] Mountpoint /home/user/data/app contains world-writable file: /home/user/data/app/file2.txt"
    expected_backup_warn = "[WARN] Mountpoint /home/user/data/backups contains world-writable file: /home/user/data/backups/backup1.tar.gz"
    expected_critical = "[CRITICAL] Mountpoint /home/user/data/missing defined in fstab_config does not exist."

    assert expected_alert in lines, f"Missing or incorrect quota alert in {log_path}. Expected: '{expected_alert}'"
    assert expected_app_warn_1 in lines, f"Missing security warning in {log_path}. Expected: '{expected_app_warn_1}'"
    assert expected_app_warn_2 in lines, f"Missing security warning in {log_path}. Expected: '{expected_app_warn_2}'"
    assert expected_backup_warn in lines, f"Missing or incorrect security warning in {log_path}. Expected: '{expected_backup_warn}'"
    assert expected_critical in lines, f"Missing or incorrect missing mountpoint critical log in {log_path}. Expected: '{expected_critical}'"

    # Ensure no extra unexpected lines are present
    assert len(lines) == 5, f"Expected exactly 5 log entries, but found {len(lines)}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
