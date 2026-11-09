#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import csv
import math

def test_anomalies_csv():
    csv_path = "/home/user/anomalies.csv"
    assert os.path.exists(csv_path), f"Output file {csv_path} does not exist. Ensure your Go program writes to this exact path."
    assert os.path.isfile(csv_path), f"Path {csv_path} is not a file."

    jsonl_path = "/home/user/telemetry.jsonl"
    assert os.path.exists(jsonl_path), f"Input file {jsonl_path} is missing."

    records_by_host = {}
    with open(jsonl_path, 'r', encoding='utf-8') as f:
        for line in f:
            if not line.strip():
                continue
            record = json.loads(line)
            # The fixture stores a literal JSON unicode escape inside the decoded
            # host string, so evaluate that escape as required by the instruction.
            host = json.loads('"' + record['host'] + '"')
            if host not in records_by_host:
                records_by_host[host] = []
            records_by_host[host].append(record)

    expected_anomalies = []

    for host, records in records_by_host.items():
        records.sort(key=lambda x: x['ts'])

        # Calculate population mean and stddev for cpu
        cpus = [r['cpu'] for r in records]
        n = len(cpus)
        mean_cpu = sum(cpus) / n if n > 0 else 0
        variance = sum((c - mean_cpu) ** 2 for c in cpus) / n if n > 0 else 0
        stddev_cpu = math.sqrt(variance)

        for i, record in enumerate(records):
            # Calculate 5-point SMA for latency
            start_idx = max(0, i - 4)
            window = records[start_idx:i+1]
            sma_latency = sum(r['latency'] for r in window) / len(window)

            # Calculate Z-score
            z_cpu = (record['cpu'] - mean_cpu) / stddev_cpu if stddev_cpu > 0 else 0.0

            if sma_latency > 150.0 and z_cpu > 1.5:
                expected_anomalies.append({
                    'ts': record['ts'],
                    'host': host,
                    'sma_latency': sma_latency,
                    'z_cpu': z_cpu
                })

    # Sort anomalies
    expected_anomalies.sort(key=lambda x: (x['ts'], x['host']))

    actual_anomalies = []
    with open(csv_path, 'r', encoding='utf-8') as f:
        reader = csv.reader(f)
        try:
            header = next(reader)
        except StopIteration:
            header = []
        assert header == ['ts', 'host', 'sma_latency', 'z_cpu'], f"CSV header is incorrect. Expected ['ts', 'host', 'sma_latency', 'z_cpu'], got: {header}"

        for row in reader:
            if not row:
                continue
            assert len(row) == 4, f"Invalid row length in CSV: {row}. Expected 4 columns."
            actual_anomalies.append({
                'ts': int(row[0]),
                'host': row[1],
                'sma_latency_str': row[2],
                'z_cpu_str': row[3]
            })

    assert len(actual_anomalies) == len(expected_anomalies), f"Expected {len(expected_anomalies)} anomalies, but found {len(actual_anomalies)} in the CSV."

    for i, (actual, expected) in enumerate(zip(actual_anomalies, expected_anomalies)):
        assert actual['ts'] == expected['ts'], f"Row {i+1}: Expected ts {expected['ts']}, got {actual['ts']}"
        assert actual['host'] == expected['host'], f"Row {i+1}: Expected host {expected['host']}, got {actual['host']}"

        expected_sma = f"{expected['sma_latency']:.2f}"
        expected_z = f"{expected['z_cpu']:.2f}"

        assert actual['sma_latency_str'] == expected_sma, f"Row {i+1} (host {actual['host']}): Expected sma_latency {expected_sma}, got {actual['sma_latency_str']}"
        assert actual['z_cpu_str'] == expected_z, f"Row {i+1} (host {actual['host']}): Expected z_cpu {expected_z}, got {actual['z_cpu_str']}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
