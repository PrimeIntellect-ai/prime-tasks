#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import csv
import base64
import pytest

def test_anomalies_txt():
    """Validate that anomalies.txt contains the correct timestamps sorted chronologically."""
    csv_path = '/home/user/sys_metrics.csv'
    anomalies_path = '/home/user/anomalies.txt'

    assert os.path.exists(anomalies_path), f"File missing: {anomalies_path}"
    assert os.path.exists(csv_path), f"Source file missing: {csv_path}"

    expected_anomalies = []
    with open(csv_path, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            if float(row['execution_duration']) > 4.0:
                expected_anomalies.append(row['timestamp'])

    # Ensure chronological order
    expected_anomalies.sort(key=lambda x: float(x))

    with open(anomalies_path, 'r') as f:
        actual_anomalies = [line.strip() for line in f if line.strip()]

    assert actual_anomalies == expected_anomalies, (
        f"Anomalies mismatch in {anomalies_path}. "
        f"Expected {len(expected_anomalies)} anomalies, found {len(actual_anomalies)}."
    )

def test_exfiltration_ip_txt():
    """Validate that exfiltration_ip.txt contains the correctly decrypted C2 IP address."""
    ip_path = '/home/user/exfiltration_ip.txt'
    assert os.path.exists(ip_path), f"File missing: {ip_path}"

    # Recompute the expected IP based on the logic in the suspicious worker
    encoded_payload = b'T1o/Tzo3ODs+TTo='
    key = 42
    decoded = base64.b64decode(encoded_payload)
    expected_ip = ''.join(chr(c ^ key) for c in decoded)

    with open(ip_path, 'r') as f:
        actual_ip = f.read().strip()

    assert actual_ip == expected_ip, (
        f"IP address mismatch in {ip_path}. "
        f"Expected '{expected_ip}', but got '{actual_ip}'."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
