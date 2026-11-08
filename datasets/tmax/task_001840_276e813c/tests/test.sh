#!/bin/bash
set -e
mkdir -p /logs/verifier

run_checks() {
    test -d /home/user/etl_pipeline || return 1
    test -f /home/user/etl_pipeline/Cargo.toml || return 1
    find /home/user/etl_pipeline/src -type f -name '*.rs' -size +0c -print -quit 2>/dev/null | grep -q . || return 1

    # Replace the public fixtures with fresh valid inputs so a precomputed output
    # cannot pass. The assertions below derive their expectations from these data.
    python3 - <<'FIXTURE_EOF' || return 1
import csv
import json
import secrets

suffix = secrets.token_hex(5)
u1 = "alpha_" + suffix
u2 = "beta_" + suffix
u3 = "gamma_" + suffix
u4 = "unmatched_" + suffix

logs = [
    {"ts": "2024-06-17T09:21:47Z", "uid": u1, "ip": "10.23.45.67", "email": "alice.smith@example.com"},
    {"ts": "2024-06-17T10:08:03Z", "uid": u2, "ip": "192.168.77.211", "email": "bob@work.test"},
    {"ts": "2024-06-18T00:59:59Z", "uid": u3, "ip": "172.31.9.8", "email": "carol.jones@company.org"},
    {"ts": "2024-06-18T12:40:15Z", "uid": u4, "ip": "8.8.4.4", "email": "nobody@example.net"},
]
transactions = [
    ["2024-06-17T09:21:01Z", u1, "31.27"],
    ["2024-06-17T09:21:58Z", u1, "8.16"],
    ["2024-06-17T10:08:44Z", u2, "100.05"],
    ["2024-06-18T00:59:02Z", u3, "0.99"],
    ["2024-06-18T12:41:15Z", u4, "700.00"],
    ["2024-06-17T09:21:20Z", "tx_only_" + suffix, "12.00"],
]

with open('/home/user/data/logs.jsonl', 'w') as f:
    for record in logs:
        f.write(json.dumps(record) + '\n')
with open('/home/user/data/tx.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['tx_ts', 'uid', 'amount'])
    writer.writerows(transactions)
FIXTURE_EOF

    rm -f /home/user/output/merged.jsonl

    # Compile the submitted Cargo project and execute its Rust binary against the
    # fresh fixtures. Use the agent user's Cargo cache and permissions.
    runuser -u user -- bash -c 'cd /home/user/etl_pipeline && HOME=/home/user timeout 240 cargo build --quiet' || return 1
    runuser -u user -- bash -c 'cd /home/user/etl_pipeline && HOME=/home/user timeout 120 cargo run --quiet' || return 1

    cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import csv

def truncate_ts(ts):
    """Truncates an ISO8601 timestamp to the minute."""
    return ts[:17] + "00Z"

def mask_ip(ip):
    """Masks the last octet of an IPv4 address."""
    parts = ip.split('.')
    if len(parts) == 4:
        parts[-1] = '0'
    return '.'.join(parts)

def mask_email(email):
    """Masks the local part of the email."""
    if '@' in email:
        local, domain = email.split('@', 1)
        if len(local) > 0:
            local = local[0] + "***"
        return f"{local}@{domain}"
    return email

def test_merged_jsonl_exists():
    assert os.path.isfile('/home/user/output/merged.jsonl'), "The output file /home/user/output/merged.jsonl is missing. Did the Rust program run successfully?"

def test_merged_jsonl_content():
    logs = {}
    logs_file = '/home/user/data/logs.jsonl'
    assert os.path.isfile(logs_file), f"Input file {logs_file} is missing."

    with open(logs_file, 'r') as f:
        for line in f:
            if line.strip():
                record = json.loads(line)
                minute = truncate_ts(record['ts'])
                uid = record['uid']
                key = (uid, minute)
                logs[key] = record

    txs = {}
    tx_file = '/home/user/data/tx.csv'
    assert os.path.isfile(tx_file), f"Input file {tx_file} is missing."

    with open(tx_file, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            minute = truncate_ts(row['tx_ts'])
            uid = row['uid']
            amount = float(row['amount'])
            key = (uid, minute)
            if key not in txs:
                txs[key] = 0.0
            txs[key] += amount

    expected_output = []
    for key in set(logs.keys()).intersection(set(txs.keys())):
        uid, minute = key
        log = logs[key]
        expected_output.append({
            "minute": minute,
            "uid": uid,
            "masked_ip": mask_ip(log['ip']),
            "masked_email": mask_email(log['email']),
            "total_amount": round(txs[key], 2)
        })

    actual_output = []
    with open('/home/user/output/merged.jsonl', 'r') as f:
        for line in f:
            if line.strip():
                try:
                    actual_output.append(json.loads(line))
                except json.JSONDecodeError:
                    assert False, f"Output file contains invalid JSON: {line.strip()}"

    expected_sorted = sorted(expected_output, key=lambda x: (x['uid'], x['minute']))
    actual_sorted = sorted(actual_output, key=lambda x: (x.get('uid', ''), x.get('minute', '')))

    assert len(expected_sorted) == len(actual_sorted), f"Expected {len(expected_sorted)} records in merged.jsonl, but found {len(actual_sorted)}."

    for exp, act in zip(expected_sorted, actual_sorted):
        assert 'minute' in act, "Missing 'minute' key in output record."
        assert exp['minute'] == act['minute'], f"Minute mismatch: expected {exp['minute']}, got {act['minute']}."

        assert 'uid' in act, "Missing 'uid' key in output record."
        assert exp['uid'] == act['uid'], f"UID mismatch: expected {exp['uid']}, got {act['uid']}."

        assert 'masked_ip' in act, "Missing 'masked_ip' key in output record."
        assert exp['masked_ip'] == act['masked_ip'], f"IP masking mismatch for uid {exp['uid']}: expected {exp['masked_ip']}, got {act['masked_ip']}."

        assert 'masked_email' in act, "Missing 'masked_email' key in output record."
        assert exp['masked_email'] == act['masked_email'], f"Email masking mismatch for uid {exp['uid']}: expected {exp['masked_email']}, got {act['masked_email']}."

        assert 'total_amount' in act, "Missing 'total_amount' key in output record."
        assert isinstance(act['total_amount'], (int, float)), f"'total_amount' should be a number for uid {exp['uid']}."
        assert abs(exp['total_amount'] - act['total_amount']) < 0.01, f"Total amount mismatch for uid {exp['uid']}: expected {exp['total_amount']}, got {act['total_amount']}."
TEST_EOF

    python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1
}

if run_checks; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
