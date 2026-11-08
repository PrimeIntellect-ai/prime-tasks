#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import csv
import hashlib
from collections import defaultdict

def derive_expected_anomalies(input_path):
    with open(input_path, 'r') as f:
        reader = csv.DictReader(f)
        data = list(reader)

    # 1. Deduplication & Reshaping
    # Group by timestamp, ip_address, metric_name -> max metric_value
    agg = defaultdict(lambda: defaultdict(lambda: float('-inf')))
    for row in data:
        ts = row['timestamp']
        ip = row['ip_address']
        metric = row['metric_name']
        val = float(row['metric_value'])
        agg[(ts, ip)][metric] = max(agg[(ts, ip)][metric], val)

    # Reshape wide
    wide = []
    for (ts, ip), metrics in agg.items():
        wide.append({
            'timestamp': ts,
            'ip_address': ip,
            'cpu_usage': metrics.get('cpu_usage', None),
        })

    # 2. Imputation: Sort by ip_address, timestamp
    wide.sort(key=lambda x: (x['ip_address'], x['timestamp']))

    # ffill cpu_usage
    last_cpu = {}
    for row in wide:
        ip = row['ip_address']
        if row['cpu_usage'] is not None:
            last_cpu[ip] = row['cpu_usage']
        else:
            row['cpu_usage'] = last_cpu.get(ip, None)

    # 3. Rolling Statistics
    cpu_history = defaultdict(list)
    for row in wide:
        ip = row['ip_address']
        if row['cpu_usage'] is not None:
            cpu_history[ip].append(row['cpu_usage'])
            if len(cpu_history[ip]) >= 3:
                row['cpu_rolling_mean'] = sum(cpu_history[ip][-3:]) / 3.0
            else:
                row['cpu_rolling_mean'] = None
        else:
            row['cpu_rolling_mean'] = None

    # 4. Anomaly Detection
    anomalies = []
    for row in wide:
        if row['cpu_rolling_mean'] is not None and row['cpu_usage'] is not None:
            if row['cpu_usage'] > 1.2 * row['cpu_rolling_mean']:
                # 5. Data Masking
                masked_ip = hashlib.sha256(row['ip_address'].encode('utf-8')).hexdigest()
                anomalies.append({
                    'timestamp': row['timestamp'],
                    'masked_ip': masked_ip,
                    'cpu_usage': f"{row['cpu_usage']:.2f}",
                    'cpu_rolling_mean': f"{row['cpu_rolling_mean']:.2f}"
                })

    return anomalies

def test_anomalies_file_exists():
    output_path = "/home/user/anomalies.csv"
    assert os.path.isfile(output_path), f"The output file {output_path} does not exist."

def test_anomalies_content():
    input_path = "/home/user/etl_metrics.csv"
    output_path = "/home/user/anomalies.csv"

    assert os.path.isfile(input_path), "Input file missing, cannot verify output."
    assert os.path.isfile(output_path), "Output file missing."

    expected_anomalies = derive_expected_anomalies(input_path)

    with open(output_path, 'r') as f:
        reader = csv.DictReader(f)
        actual_headers = reader.fieldnames
        actual_anomalies = list(reader)

    expected_headers = ['timestamp', 'masked_ip', 'cpu_usage', 'cpu_rolling_mean']
    assert actual_headers == expected_headers, f"Output CSV headers are incorrect. Expected {expected_headers}, got {actual_headers}."

    # Compare rows (ignoring order)
    def normalize_row(row):
        return (row['timestamp'], row['masked_ip'], float(row['cpu_usage']), float(row['cpu_rolling_mean']))

    try:
        expected_set = set(normalize_row(r) for r in expected_anomalies)
    except Exception as e:
        assert False, f"Failed to parse expected anomalies: {e}"

    try:
        actual_set = set(normalize_row(r) for r in actual_anomalies)
    except Exception as e:
        assert False, f"Failed to parse actual anomalies. Ensure values are numeric. Error: {e}"

    missing = expected_set - actual_set
    extra = actual_set - expected_set

    error_msg = []
    if missing:
        error_msg.append(f"Missing expected anomalies: {missing}")
    if extra:
        error_msg.append(f"Unexpected anomalies found: {extra}")

    assert not missing and not extra, "\n".join(error_msg)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
