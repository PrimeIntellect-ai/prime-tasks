#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import json
from scipy.stats import ttest_1samp


def test_training_features_exists_and_format():
    output_path = '/home/user/training_features.csv'
    assert os.path.isfile(output_path), f"Output file {output_path} is missing."

    with open(output_path, 'r', encoding='utf-8') as f:
        reader = csv.reader(f)
        header = next(reader, None)
        assert header is not None, "Output CSV is empty."

        expected_header = ['node_id', 'datacenter', 'total_requests', 'bayes_failure_rate', 'latency_pvalue', 'is_anomalous']
        assert header == expected_header, f"CSV header incorrect. Expected {expected_header}, got {header}"

        rows = list(reader)
        assert len(rows) > 0, "Output CSV has no data rows."

        # Check sorting by node_id
        node_ids = [row[0] for row in rows]
        assert node_ids == sorted(node_ids), "CSV is not sorted alphabetically by node_id."
        assert len(node_ids) == len(set(node_ids)), "CSV contains duplicate node_id rows."


def test_training_features_values():
    output_path = '/home/user/training_features.csv'
    assert os.path.isfile(output_path), f"Output file {output_path} is missing."

    # 1. Read node info
    node_info_path = '/home/user/node_info.json'
    with open(node_info_path, 'r', encoding='utf-8') as f:
        node_info = json.load(f)
    datacenter_map = {n['node_id']: n['datacenter'] for n in node_info}

    # 2. Read logs and compute aggregates
    logs_path = '/home/user/api_logs.csv'
    node_stats = {}
    with open(logs_path, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            nid = row['node_id']
            status = row['status']
            latency = float(row['latency_ms'])

            if nid not in node_stats:
                node_stats[nid] = {'total': 0, 'fails': 0, 'success_lats': []}

            node_stats[nid]['total'] += 1
            if status == 'fail':
                node_stats[nid]['fails'] += 1
            elif status == 'success':
                node_stats[nid]['success_lats'].append(latency)

    # 3. Read student output and verify
    with open(output_path, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        student_rows = list(reader)

    assert len(student_rows) == len(node_stats), f"Expected {len(node_stats)} rows, got {len(student_rows)}."
    student_node_ids = [row['node_id'] for row in student_rows]
    assert len(student_node_ids) == len(set(student_node_ids)), "Output contains duplicate node_id rows."
    assert set(student_node_ids) == set(node_stats), "Output must contain exactly one row for every node_id in the logs."

    for row in student_rows:
        nid = row['node_id']
        assert nid in node_stats, f"Unexpected node_id {nid} in output."

        stats = node_stats[nid]

        # Datacenter
        expected_dc = datacenter_map.get(nid, '')
        assert row['datacenter'] == expected_dc, f"Incorrect datacenter for {nid}. Expected {expected_dc}, got {row['datacenter']}"

        # Total requests
        expected_total = stats['total']
        assert int(row['total_requests']) == expected_total, f"Incorrect total_requests for {nid}."

        # Bayes failure rate
        alpha, beta = 2, 10
        expected_bayes = (alpha + stats['fails']) / (alpha + beta + expected_total)
        expected_bayes_round = round(expected_bayes, 4)
        assert float(row['bayes_failure_rate']) == expected_bayes_round, f"Incorrect bayes_failure_rate for {nid}. Expected {expected_bayes_round}, got {row['bayes_failure_rate']}"

        # Latency p-value and anomaly logic
        success_lats = stats['success_lats']
        student_pvalue = float(row['latency_pvalue'])

        if len(success_lats) < 2:
            expected_pvalue = 1.0
            assert student_pvalue == 1.0, f"Expected latency_pvalue of 1.0 for {nid} (fewer than 2 successes), got {student_pvalue}."
            mean_lat = 0.0
        else:
            assert 0.0 <= student_pvalue <= 1.0, f"Invalid p-value {student_pvalue} for {nid}."
            expected_pvalue = round(float(ttest_1samp(success_lats, popmean=120.0).pvalue), 4)
            assert student_pvalue == expected_pvalue, f"Incorrect latency_pvalue for {nid}. Expected {expected_pvalue}, got {student_pvalue}."
            mean_lat = sum(success_lats) / len(success_lats)

        # Is anomalous
        expected_anomaly = 1 if (expected_bayes > 0.15) or (expected_pvalue < 0.05 and mean_lat > 120.0) else 0
        assert int(row['is_anomalous']) == expected_anomaly, f"Incorrect is_anomalous for {nid}. Expected {expected_anomaly}, got {row['is_anomalous']}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
