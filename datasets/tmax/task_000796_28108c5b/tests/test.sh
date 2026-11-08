#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import re
from datetime import datetime, timezone
import math

def parse_timestamp(ts_str):
    if 'T' in ts_str:
        dt = datetime.strptime(ts_str, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
        return int(dt.timestamp())
    else:
        return int(ts_str)

def compute_expected_state(log_file):
    servers = {}
    with open(log_file, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            match = re.match(r'^\[(.*?)\] Server: (.*?) \| Key: (.*?) \| Value: (.*)$', line)
            if match:
                ts_str, server, key, value = match.groups()
                ts = parse_timestamp(ts_str)
                is_sensitive = any(sub in key.lower() for sub in ["pass", "secret", "token"])

                if server not in servers:
                    servers[server] = {"timestamps": [], "masked_count": 0}

                servers[server]["timestamps"].append(ts)
                if is_sensitive:
                    servers[server]["masked_count"] += 1

    result = {}
    for server, data in servers.items():
        timestamps = sorted(data["timestamps"])
        latest = timestamps[-1] if timestamps else 0
        masked = data["masked_count"]

        intervals = [timestamps[i] - timestamps[i-1] for i in range(1, len(timestamps))]
        if len(intervals) < 2:
            variance = 0.0
        else:
            mean = sum(intervals) / len(intervals)
            variance = sum((x - mean) ** 2 for x in intervals) / len(intervals)

        result[server] = {
            "masked_count": masked,
            "interval_variance": round(variance, 2),
            "latest_change_epoch": latest
        }

    return result

def test_config_summary_json():
    log_file = "/home/user/config_changes.log"
    json_file = "/home/user/config_summary.json"

    assert os.path.exists(log_file), f"Log file {log_file} is missing."
    assert os.path.exists(json_file), f"Output JSON file {json_file} is missing. The Rust program may not have generated it."

    with open(json_file, "r") as f:
        try:
            actual_data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"Output file {json_file} contains invalid JSON."

    expected_data = compute_expected_state(log_file)

    assert isinstance(actual_data, dict), "The root of the JSON output must be an object/dictionary."
    assert set(actual_data.keys()) == set(expected_data.keys()), f"Server IPs in JSON do not match expected. Expected: {list(expected_data.keys())}, Actual: {list(actual_data.keys())}"

    for server, expected_metrics in expected_data.items():
        actual_metrics = actual_data[server]

        # Check masked_count
        assert "masked_count" in actual_metrics, f"Missing 'masked_count' for server {server}"
        assert actual_metrics["masked_count"] == expected_metrics["masked_count"], f"Incorrect 'masked_count' for server {server}. Expected {expected_metrics['masked_count']}, got {actual_metrics['masked_count']}"

        # Check latest_change_epoch
        assert "latest_change_epoch" in actual_metrics, f"Missing 'latest_change_epoch' for server {server}"
        assert actual_metrics["latest_change_epoch"] == expected_metrics["latest_change_epoch"], f"Incorrect 'latest_change_epoch' for server {server}. Expected {expected_metrics['latest_change_epoch']}, got {actual_metrics['latest_change_epoch']}"

        # Check interval_variance
        assert "interval_variance" in actual_metrics, f"Missing 'interval_variance' for server {server}"
        actual_variance = float(actual_metrics["interval_variance"])
        expected_variance = expected_metrics["interval_variance"]
        assert math.isclose(actual_variance, expected_variance, abs_tol=0.01), f"Incorrect 'interval_variance' for server {server}. Expected {expected_variance}, got {actual_variance}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
