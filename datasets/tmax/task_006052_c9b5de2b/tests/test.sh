#!/bin/bash
set -e
mkdir -p /logs/verifier

trusted_dir=$(mktemp -d /tmp/trusted_raw_logs.XXXXXX)
chmod 700 "$trusted_dir"

python3 - "$trusted_dir" <<'FIXTURE_EOF'
import datetime
import os
import sys

raw_logs_dir = sys.argv[1]
start_epoch = 1696154400
logs_eu = []
logs_us = []
logs_asia = []

for m in range(60):
    current_epoch = start_epoch + (m * 60)
    dt = datetime.datetime.utcfromtimestamp(current_epoch)
    latency_ms = 400.0 if 25 <= m < 30 else 100.0

    eu_time = dt.strftime("%d/%m/%Y %H:%M:%S")
    logs_eu.append(f"{eu_time} | OK\xa0 | {latency_ms}")

    us_time = dt.strftime("%Y-%m-%dT%H:%M:%SZ")
    logs_us.append(f"{us_time} | OK | {latency_ms / 1000.0}")

    asia_time = int(current_epoch * 1000)
    logs_asia.append(f"{asia_time} | OK | {latency_ms * 1000.0}")

with open(os.path.join(raw_logs_dir, "server_eu.log"), "w", encoding="iso-8859-1") as f:
    f.write("\n".join(logs_eu))
with open(os.path.join(raw_logs_dir, "server_us.log"), "w", encoding="utf-8") as f:
    f.write("\n".join(logs_us))
with open(os.path.join(raw_logs_dir, "server_asia.log"), "w", encoding="utf-16le") as f:
    f.write("\n".join(logs_asia))
FIXTURE_EOF

export TRUSTED_RAW_LOGS_DIR="$trusted_dir"

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import datetime
from collections import defaultdict

def parse_eu_time(t_str):
    dt = datetime.datetime.strptime(t_str, "%d/%m/%Y %H:%M:%S")
    return int(dt.replace(tzinfo=datetime.timezone.utc).timestamp())

def parse_us_time(t_str):
    dt = datetime.datetime.strptime(t_str, "%Y-%m-%dT%H:%M:%SZ")
    return int(dt.replace(tzinfo=datetime.timezone.utc).timestamp())

def parse_asia_time(t_str):
    return int(t_str) // 1000

def compute_expected_anomalies():
    raw_logs_dir = os.environ["TRUSTED_RAW_LOGS_DIR"]
    eu_log = os.path.join(raw_logs_dir, "server_eu.log")
    us_log = os.path.join(raw_logs_dir, "server_us.log")
    asia_log = os.path.join(raw_logs_dir, "server_asia.log")

    entries = []

    if os.path.exists(eu_log):
        with open(eu_log, 'r', encoding='iso-8859-1') as f:
            for line in f:
                line = line.strip()
                if not line: continue
                parts = [p.strip() for p in line.split('|')]
                epoch = parse_eu_time(parts[0])
                latency_ms = float(parts[2])
                entries.append((epoch, latency_ms))

    if os.path.exists(us_log):
        with open(us_log, 'r', encoding='utf-8') as f:
            for line in f:
                line = line.strip()
                if not line: continue
                parts = [p.strip() for p in line.split('|')]
                epoch = parse_us_time(parts[0])
                latency_ms = float(parts[2]) * 1000.0
                entries.append((epoch, latency_ms))

    if os.path.exists(asia_log):
        with open(asia_log, 'r', encoding='utf-16le') as f:
            for line in f:
                line = line.strip()
                if not line: continue
                parts = [p.strip() for p in line.split('|')]
                epoch = parse_asia_time(parts[0])
                latency_ms = float(parts[2]) / 1000.0
                entries.append((epoch, latency_ms))

    buckets = defaultdict(list)
    for epoch, lat in entries:
        bucket_start = (epoch // 300) * 300
        buckets[bucket_start].append(lat)

    bucket_means = {}
    for b_start, lats in buckets.items():
        bucket_means[b_start] = sum(lats) / len(lats)

    sorted_buckets = sorted(bucket_means.keys())

    anomalies = []
    for i in range(1, len(sorted_buckets)):
        curr_b = sorted_buckets[i]
        prev_b = sorted_buckets[i-1]
        curr_mean = bucket_means[curr_b]
        prev_mean = bucket_means[prev_b]

        if curr_mean > 2.5 * prev_mean:
            anomalies.append({
                'bucket_start_epoch': str(curr_b),
                'avg_latency_ms': f"{curr_mean:.2f}",
                'prev_avg_latency_ms': f"{prev_mean:.2f}"
            })

    return anomalies

def test_anomalies_csv_exists():
    csv_path = "/home/user/anomalies.csv"
    assert os.path.isfile(csv_path), f"Expected output file {csv_path} does not exist."

def test_anomalies_csv_content():
    csv_path = "/home/user/anomalies.csv"
    assert os.path.isfile(csv_path), f"Expected output file {csv_path} does not exist."

    expected_anomalies = compute_expected_anomalies()

    with open(csv_path, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == ['bucket_start_epoch', 'avg_latency_ms', 'prev_avg_latency_ms'], \
            f"CSV header is incorrect. Expected ['bucket_start_epoch', 'avg_latency_ms', 'prev_avg_latency_ms'], got {reader.fieldnames}"

        rows = list(reader)

    assert len(rows) == len(expected_anomalies), \
        f"Expected {len(expected_anomalies)} anomalies, but found {len(rows)} in the CSV."

    for i, (expected, actual) in enumerate(zip(expected_anomalies, rows)):
        assert actual['bucket_start_epoch'] == expected['bucket_start_epoch'], \
            f"Row {i+1}: Expected bucket_start_epoch {expected['bucket_start_epoch']}, got {actual['bucket_start_epoch']}"
        assert actual['avg_latency_ms'] == expected['avg_latency_ms'], \
            f"Row {i+1}: Expected avg_latency_ms {expected['avg_latency_ms']}, got {actual['avg_latency_ms']}"
        assert actual['prev_avg_latency_ms'] == expected['prev_avg_latency_ms'], \
            f"Row {i+1}: Expected prev_avg_latency_ms {expected['prev_avg_latency_ms']}, got {actual['prev_avg_latency_ms']}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

rm -rf "$trusted_dir"
