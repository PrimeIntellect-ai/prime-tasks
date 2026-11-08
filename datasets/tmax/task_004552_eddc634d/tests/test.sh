#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import csv
import math

def compute_expected_result(csv_path):
    # 1. Read CSV and Deduplicate (keep last)
    records = {}
    metrics_set = set()
    servers_set = set()
    ts_set = set()

    with open(csv_path, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            ts = int(row['ts'])
            server = row['server']
            metric = row['metric']
            value = float(row['value'])

            records[(ts, server, metric)] = value
            metrics_set.add(metric)
            servers_set.add(server)
            ts_set.add(ts)

    metrics = sorted(list(metrics_set))
    servers = sorted(list(servers_set))
    timestamps = sorted(list(ts_set))

    # 2 & 3. Reshape and Impute
    # For each server and metric, we need a complete time series
    server_profiles = {}

    for server in servers:
        server_profiles[server] = {}
        for metric in metrics:
            # Extract time series for this server and metric
            ts_values = {}
            for ts in timestamps:
                if (ts, server, metric) in records:
                    ts_values[ts] = records[(ts, server, metric)]

            # Linear Interpolation
            for i, ts in enumerate(timestamps):
                if ts not in ts_values:
                    # Find prev
                    prev_ts = None
                    prev_val = None
                    for j in range(i - 1, -1, -1):
                        if timestamps[j] in ts_values:
                            prev_ts = timestamps[j]
                            prev_val = ts_values[prev_ts]
                            break

                    # Find next
                    next_ts = None
                    next_val = None
                    for j in range(i + 1, len(timestamps)):
                        if timestamps[j] in ts_values:
                            next_ts = timestamps[j]
                            next_val = ts_values[next_ts]
                            break

                    if prev_ts is not None and next_ts is not None:
                        # Interpolate
                        slope = (next_val - prev_val) / (next_ts - prev_ts)
                        ts_values[ts] = prev_val + slope * (ts - prev_ts)

            # Bfill (missing at beginning)
            for i, ts in enumerate(timestamps):
                if ts not in ts_values:
                    # Find first available
                    for j in range(i + 1, len(timestamps)):
                        if timestamps[j] in ts_values:
                            ts_values[ts] = ts_values[timestamps[j]]
                            break

            # Ffill (missing at end)
            for i in range(len(timestamps) - 1, -1, -1):
                ts = timestamps[i]
                if ts not in ts_values:
                    # Find last available
                    for j in range(i - 1, -1, -1):
                        if timestamps[j] in ts_values:
                            ts_values[ts] = ts_values[timestamps[j]]
                            break

            # 4. Similarity Computation (average profile)
            avg_val = sum(ts_values[ts] for ts in timestamps) / len(timestamps)
            server_profiles[server][metric] = avg_val

    # 5. Distance Calculation
    min_dist = float('inf')
    closest_pair = None

    for i in range(len(servers)):
        for j in range(i + 1, len(servers)):
            s1 = servers[i]
            s2 = servers[j]

            dist_sq = 0
            for metric in metrics:
                dist_sq += (server_profiles[s1][metric] - server_profiles[s2][metric]) ** 2
            dist = math.sqrt(dist_sq)

            if dist < min_dist:
                min_dist = dist
                closest_pair = (s1, s2)

    return {
        "server1": closest_pair[0],
        "server2": closest_pair[1],
        "distance": round(min_dist, 4)
    }

def test_closest_servers_json():
    csv_path = "/home/user/raw_metrics.csv"
    json_path = "/home/user/closest_servers.json"

    assert os.path.exists(json_path), f"Output file {json_path} is missing."

    with open(json_path, 'r', encoding='utf-8') as f:
        try:
            actual_data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"File {json_path} is not valid JSON."

    assert "server1" in actual_data, "Key 'server1' is missing in JSON."
    assert "server2" in actual_data, "Key 'server2' is missing in JSON."
    assert "distance" in actual_data, "Key 'distance' is missing in JSON."

    expected_data = compute_expected_result(csv_path)

    assert actual_data["server1"] == expected_data["server1"], f"Expected server1 to be {expected_data['server1']}, got {actual_data['server1']}"
    assert actual_data["server2"] == expected_data["server2"], f"Expected server2 to be {expected_data['server2']}, got {actual_data['server2']}"

    # Check distance with 4 decimal places
    actual_distance = actual_data["distance"]
    expected_distance = expected_data["distance"]

    assert isinstance(actual_distance, (int, float)), "Distance must be a number."
    assert round(actual_distance, 4) == expected_distance, f"Expected distance {expected_distance}, got {actual_distance}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
