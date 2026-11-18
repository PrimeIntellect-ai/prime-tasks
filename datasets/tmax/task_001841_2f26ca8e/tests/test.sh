#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import re
import pytest

REPORT_PATH = "/home/user/incident_report.json"
LOG_PATH = "/home/user/incident_data/service.log"
WAL_PATH = "/home/user/incident_data/transactions.wal"

def get_expected_deadlock_threads():
    with open(LOG_PATH, 'r') as f:
        lines = f.readlines()

    acquired = {}
    waiting = {}
    for line in lines:
        match_acq = re.search(r'\[(.*?)\] \[INFO\] Acquired (.*)', line)
        if match_acq:
            thread_id, resource = match_acq.groups()
            acquired[resource] = thread_id

        match_wait = re.search(r'\[(.*?)\] \[WAIT\] Waiting for (.*)', line)
        if match_wait:
            thread_id, resource = match_wait.groups()
            waiting[thread_id] = resource

    # Find deadlock
    deadlocked = set()
    for t1, r1 in waiting.items():
        if r1 in acquired:
            t2 = acquired[r1]
            if t2 in waiting:
                r2 = waiting[t2]
                if r2 in acquired and acquired[r2] == t1:
                    deadlocked.add(t1)
                    deadlocked.add(t2)
    return deadlocked

def get_expected_wal_info():
    with open(WAL_PATH, 'r') as f:
        lines = f.read().splitlines()

    valid_txns = []
    for line in lines:
        parts = line.split(':')
        if len(parts) == 4 and len(parts[3]) == 8 and parts[3].isalnum():
            valid_txns.append({
                'id': parts[0],
                'start': float(parts[1]),
                'end': float(parts[2])
            })

    last_recovered = valid_txns[-1]['id'] if valid_txns else None

    durations = [(txn['end'] - txn['start']) for txn in valid_txns]
    durations.sort()
    median = durations[len(durations)//2]

    anomalous_txn = None
    for txn in valid_txns:
        if (txn['end'] - txn['start']) >= 10 * median:
            anomalous_txn = txn['id']
            break

    return anomalous_txn, last_recovered

def test_incident_report_exists():
    assert os.path.isfile(REPORT_PATH), f"Expected incident report at {REPORT_PATH} was not found."

def test_incident_report_format_and_values():
    with open(REPORT_PATH, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {REPORT_PATH} is not valid JSON.")

    expected_deadlocked_threads = get_expected_deadlock_threads()
    expected_anomaly, expected_last = get_expected_wal_info()

    # Check Deadlocks
    assert 'deadlock_thread_1' in data, "Missing key 'deadlock_thread_1'"
    assert 'deadlock_thread_2' in data, "Missing key 'deadlock_thread_2'"

    actual_threads = {data['deadlock_thread_1'], data['deadlock_thread_2']}
    assert actual_threads == expected_deadlocked_threads, \
        f"Expected deadlocked threads {expected_deadlocked_threads}, got {actual_threads}"

    # Check Anomaly
    assert 'anomalous_txn_id' in data, "Missing key 'anomalous_txn_id'"
    assert data['anomalous_txn_id'] == expected_anomaly, \
        f"Expected anomalous_txn_id to be {expected_anomaly}, got {data['anomalous_txn_id']}"

    # Check Last Recovered
    assert 'last_recovered_txn_id' in data, "Missing key 'last_recovered_txn_id'"
    assert data['last_recovered_txn_id'] == expected_last, \
        f"Expected last_recovered_txn_id to be {expected_last}, got {data['last_recovered_txn_id']}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
