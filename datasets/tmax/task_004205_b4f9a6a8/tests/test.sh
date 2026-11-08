#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import csv

def test_closest_server_identified():
    csv_path = '/home/user/servers.csv'
    result_path = '/home/user/similar_host.txt'

    assert os.path.isfile(csv_path), f"File {csv_path} is missing."
    assert os.path.isfile(result_path), f"File {result_path} is missing."

    target_cpu = 85.0
    target_mem = 20.0
    target_disk = 60.0

    closest_host = None
    min_distance = float('inf')

    with open(csv_path, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            cpu = float(row['cpu'])
            mem = float(row['mem'])
            disk = float(row['disk'])

            # Squared Euclidean distance
            distance = (cpu - target_cpu)**2 + (mem - target_mem)**2 + (disk - target_disk)**2

            if distance < min_distance:
                min_distance = distance
                closest_host = row['host']

    assert closest_host is not None, "Could not determine the closest host from the CSV."

    with open(result_path, 'r') as f:
        actual_host = f.read().strip()

    assert actual_host == closest_host, f"Expected closest host '{closest_host}', but found '{actual_host}' in {result_path}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
