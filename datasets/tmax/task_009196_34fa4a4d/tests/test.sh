#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os

def test_lock_file_removed():
    lock_path = '/home/user/legacy_app/export.lock'
    assert not os.path.exists(lock_path), f"Lock file {lock_path} should have been deleted."

def test_success_log():
    log_path = '/home/user/legacy_app/success.log'
    assert os.path.exists(log_path), f"Log file {log_path} does not exist."
    with open(log_path, 'r', encoding='utf-8') as f:
        content = f.read().strip()
    assert content == "3", f"Expected success.log to contain '3', but found '{content}'."

def test_export_csv():
    csv_path = '/home/user/legacy_app/export.csv'
    assert os.path.exists(csv_path), f"Output file {csv_path} does not exist."

    try:
        with open(csv_path, 'r', encoding='utf-8') as f:
            lines = [line.strip() for line in f if line.strip()]
    except UnicodeDecodeError:
        assert False, f"Output file {csv_path} is not valid UTF-8."

    expected_lines = [
        "Item,Price",
        "Apple,1.20",
        "Café,12.50",
        "Jalapeño,5.00"
    ]

    assert lines == expected_lines, f"CSV content does not match expected output. Found: {lines}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
