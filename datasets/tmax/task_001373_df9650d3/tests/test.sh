#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import math
from collections import defaultdict

def compute_truth():
    input_file = '/home/user/tm_metrics_wide.csv'
    assert os.path.exists(input_file), f"Input file missing: {input_file}"

    records = defaultdict(list)

    with open(input_file, 'r', newline='') as f:
        reader = csv.DictReader(f)
        for row in reader:
            ts = int(row['timestamp_sec'])
            src = int(row['src_chars'])
            bucket_ts = (ts // 3600) * 3600

            for lang in ['es', 'fr', 'de']:
                lat = int(row[f'lat_{lang}'])
                chars = int(row[f'chars_{lang}'])

                if lat != -1:
                    expansion_ratio = chars / src
                    records[(lang, bucket_ts)].append((lat, expansion_ratio))

    summary = []
    lang_latencies = defaultdict(list)

    for (lang, bucket_ts), values in records.items():
        avg_lat = sum(v[0] for v in values) / len(values)
        avg_exp = sum(v[1] for v in values) / len(values)
        summary.append({
            'bucket_ts': bucket_ts,
            'language': lang,
            'avg_latency': avg_lat,
            'avg_expansion_ratio': avg_exp
        })
        lang_latencies[lang].append(avg_lat)

    lang_stats = {}
    for lang, lats in lang_latencies.items():
        mean_lat = sum(lats) / len(lats)
        variance = sum((x - mean_lat) ** 2 for x in lats) / len(lats)
        std_lat = math.sqrt(variance)
        lang_stats[lang] = (mean_lat, std_lat)

    truth_summary = []
    truth_anomalies = []

    for s in summary:
        lang = s['language']
        mean_lat, std_lat = lang_stats[lang]
        z_score = (s['avg_latency'] - mean_lat) / std_lat if std_lat > 0 else 0.0

        row = {
            'bucket_ts': s['bucket_ts'],
            'language': lang,
            'avg_latency': s['avg_latency'],
            'avg_expansion_ratio': s['avg_expansion_ratio'],
            'latency_zscore': z_score
        }
        truth_summary.append(row)

        if z_score > 2.0:
            truth_anomalies.append({
                'bucket_ts': s['bucket_ts'],
                'language': lang,
                'latency_zscore': z_score
            })

    truth_summary.sort(key=lambda x: (x['language'], x['bucket_ts']))
    truth_anomalies.sort(key=lambda x: (x['language'], x['bucket_ts']))

    return truth_summary, truth_anomalies

def read_csv_output(filepath):
    assert os.path.exists(filepath), f"Output file missing: {filepath}"
    with open(filepath, 'r', newline='') as f:
        reader = csv.DictReader(f)
        return list(reader)

def test_summary_csv():
    truth_summary, _ = compute_truth()
    agent_summary = read_csv_output('/home/user/summary.csv')

    assert len(agent_summary) == len(truth_summary), f"Summary length mismatch: expected {len(truth_summary)}, got {len(agent_summary)}"

    for i, (agent_row, truth_row) in enumerate(zip(agent_summary, truth_summary)):
        assert int(agent_row['bucket_ts']) == truth_row['bucket_ts'], f"Row {i}: bucket_ts mismatch"
        assert agent_row['language'] == truth_row['language'], f"Row {i}: language mismatch"

        for col in ['avg_latency', 'avg_expansion_ratio', 'latency_zscore']:
            agent_val = float(agent_row[col])
            truth_val = truth_row[col]
            assert math.isclose(agent_val, truth_val, abs_tol=1e-3), \
                f"Row {i} column {col} mismatch: expected {truth_val:.4f}, got {agent_val:.4f}"

def test_anomalies_csv():
    _, truth_anomalies = compute_truth()
    agent_anomalies = read_csv_output('/home/user/anomalies.csv')

    assert len(agent_anomalies) == len(truth_anomalies), f"Anomalies length mismatch: expected {len(truth_anomalies)}, got {len(agent_anomalies)}"

    for i, (agent_row, truth_row) in enumerate(zip(agent_anomalies, truth_anomalies)):
        assert int(agent_row['bucket_ts']) == truth_row['bucket_ts'], f"Row {i}: bucket_ts mismatch"
        assert agent_row['language'] == truth_row['language'], f"Row {i}: language mismatch"

        agent_val = float(agent_row['latency_zscore'])
        truth_val = truth_row['latency_zscore']
        assert math.isclose(agent_val, truth_val, abs_tol=1e-3), \
            f"Row {i} latency_zscore mismatch: expected {truth_val:.4f}, got {agent_val:.4f}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
