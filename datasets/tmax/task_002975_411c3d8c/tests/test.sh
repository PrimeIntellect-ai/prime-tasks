#!/bin/bash
mkdir -p /logs/verifier
reward=0

SCRIPT_FILE="/home/user/scripts/process.sh"
TOTAL_BYTES_FILE="/home/user/total_bytes.txt"
FIRST_LARGE_TX_FILE="/home/user/first_large_tx.txt"

# Require the requested artifact to be a real script file, then remove any
# pre-created answers so only execution of the script can produce them.
if [[ -f "$SCRIPT_FILE" && ! -L "$SCRIPT_FILE" ]]; then
    rm -f "$TOTAL_BYTES_FILE" "$FIRST_LARGE_TX_FILE"

    if [[ ! -e "$TOTAL_BYTES_FILE" && ! -e "$FIRST_LARGE_TX_FILE" ]] && \
       timeout 30s runuser -u user -- bash "$SCRIPT_FILE"; then

        cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

LOG_FILE = "/home/user/telemetry_logs/raw_data.log"
TOTAL_BYTES_FILE = "/home/user/total_bytes.txt"
FIRST_LARGE_TX_FILE = "/home/user/first_large_tx.txt"
THRESHOLD = 9007199254740992

@pytest.fixture(scope="module")
def parsed_log_data():
    assert os.path.isfile(LOG_FILE), f"Log file missing: {LOG_FILE}"

    with open(LOG_FILE, 'rb') as f:
        raw_bytes = f.read()

    try:
        decoded_text = raw_bytes.decode('utf-16le')
    except UnicodeDecodeError:
        pytest.fail(f"Log file {LOG_FILE} is no longer valid UTF-16LE.")

    records = []
    for line in decoded_text.strip().split('\n'):
        if not line.strip():
            continue
        try:
            records.append(json.loads(line))
        except json.JSONDecodeError:
            pytest.fail(f"Invalid JSON in log file: {line}")

    return records

def test_total_bytes_calculated_correctly(parsed_log_data):
    assert os.path.isfile(TOTAL_BYTES_FILE), f"Output file missing: {TOTAL_BYTES_FILE}"

    expected_sum = sum(record.get('bytes', 0) for record in parsed_log_data)

    with open(TOTAL_BYTES_FILE, 'r', encoding='utf-8') as f:
        actual_sum_str = f.read().strip()

    assert actual_sum_str.isdigit(), f"File {TOTAL_BYTES_FILE} does not contain a valid integer: '{actual_sum_str}'"
    actual_sum = int(actual_sum_str)

    assert actual_sum == expected_sum, f"Expected total sum {expected_sum}, but got {actual_sum} in {TOTAL_BYTES_FILE}"

def test_first_large_tx_identified_correctly(parsed_log_data):
    assert os.path.isfile(FIRST_LARGE_TX_FILE), f"Output file missing: {FIRST_LARGE_TX_FILE}"

    expected_tx_id = None
    for record in parsed_log_data:
        if record.get('bytes', 0) > THRESHOLD:
            expected_tx_id = record.get('tx_id')
            break

    assert expected_tx_id is not None, f"No transaction found with bytes > {THRESHOLD} in the log file."

    with open(FIRST_LARGE_TX_FILE, 'r', encoding='utf-8') as f:
        actual_tx_id = f.read().strip()

    assert actual_tx_id == expected_tx_id, f"Expected first large tx_id to be '{expected_tx_id}', but got '{actual_tx_id}' in {FIRST_LARGE_TX_FILE}"
TEST_EOF

        if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
            reward=1
        fi
    fi
fi

echo "$reward" > /logs/verifier/reward.txt
