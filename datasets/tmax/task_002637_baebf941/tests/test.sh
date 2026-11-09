#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import re
import subprocess
import sys
from collections import defaultdict

PIPELINE = "/home/user/pipeline.py"
AGENT_FILE = "/home/user/anomalies.csv"
EXPECTED_COLUMNS = ["bucket_start_timestamp", "unique_ips", "distance"]


def derive_truth():
    try:
        output = subprocess.check_output(["/app/log_emitter"], text=True, timeout=30)
    except Exception as e:
        assert False, f"Failed to run /app/log_emitter: {e}"

    buckets = defaultdict(lambda: {"ips": set(), "login": 0, "data": 0, "health": 0})

    for line in output.splitlines():
        cleaned = line.replace("\\uXX12", "")
        try:
            data = json.loads(cleaned)
            ts = data["timestamp"]
            b_start = (ts // 60) * 60

            ip_parts = data["client_ip"].split(".")
            ip_parts[3] = "0"
            masked_ip = ".".join(ip_parts)
            buckets[b_start]["ips"].add(masked_ip)

            ep = data["endpoint"]
            if ep == "/login":
                buckets[b_start]["login"] += 1
            elif ep == "/data":
                buckets[b_start]["data"] += 1
            elif ep == "/health":
                buckets[b_start]["health"] += 1
        except Exception:
            pass

    truth = {}
    for b_start, b_data in buckets.items():
        vector = [b_data["login"], b_data["data"], b_data["health"]]
        baseline = [15, 45, 10]
        distance = math.sqrt(sum((a - b) ** 2 for a, b in zip(vector, baseline)))
        truth[str(b_start)] = {
            "unique_ips": len(b_data["ips"]),
            "distance": distance,
        }
    return truth


def test_pipeline_and_anomalies_csv():
    truth = derive_truth()
    truth_distances = {bucket: values["distance"] for bucket, values in truth.items()}

    assert os.path.isfile(PIPELINE), f"Pipeline script not found at {PIPELINE}"
    if os.path.lexists(AGENT_FILE):
        os.remove(AGENT_FILE)

    try:
        result = subprocess.run(
            [sys.executable, PIPELINE],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=60,
        )
    except Exception as e:
        assert False, f"Failed to execute {PIPELINE}: {e}"

    assert result.returncode == 0, (
        f"Pipeline exited with status {result.returncode}. stderr: {result.stderr}"
    )
    assert os.path.isfile(AGENT_FILE), f"Agent output file not found at {AGENT_FILE}"

    mse = 0.0
    count = 0
    seen_buckets = set()

    try:
        with open(AGENT_FILE, "r", newline="") as f:
            reader = csv.DictReader(f)
            assert reader.fieldnames == EXPECTED_COLUMNS, (
                f"CSV columns must be exactly {EXPECTED_COLUMNS}, got {reader.fieldnames}"
            )

            for row in reader:
                assert None not in row, "CSV row has more fields than the header"
                assert all(row[column] is not None for column in EXPECTED_COLUMNS), \
                    "CSV row is missing a required field"

                b_ts = row["bucket_start_timestamp"]
                assert re.fullmatch(r"\d+", b_ts or ""), \
                    f"Invalid integer bucket_start_timestamp: {b_ts!r}"
                assert b_ts not in seen_buckets, f"Duplicate bucket in CSV: {b_ts}"
                seen_buckets.add(b_ts)

                assert b_ts in truth_distances, f"Unexpected bucket in CSV: {b_ts}"

                unique_ips_text = row["unique_ips"]
                assert re.fullmatch(r"\d+", unique_ips_text or ""), \
                    f"Invalid unique_ips value for bucket {b_ts}: {unique_ips_text!r}"
                assert int(unique_ips_text) == truth[b_ts]["unique_ips"], (
                    f"Incorrect unique_ips for bucket {b_ts}: got {unique_ips_text}, "
                    f"expected {truth[b_ts]['unique_ips']}"
                )

                distance_text = row["distance"]
                assert re.fullmatch(r"\d+\.\d{4}", distance_text or ""), (
                    f"Distance for bucket {b_ts} must have exactly 4 decimal places"
                )
                agent_dist = float(distance_text)
                expected_rounded = round(truth_distances[b_ts], 4)
                assert math.isclose(agent_dist, expected_rounded, rel_tol=0.0, abs_tol=5e-5), (
                    f"Incorrect distance for bucket {b_ts}: got {agent_dist}, "
                    f"expected {expected_rounded:.4f}"
                )

                mse += (agent_dist - truth_distances[b_ts]) ** 2
                count += 1
    except Exception as e:
        assert False, f"Error reading agent output {AGENT_FILE}: {e}"

    assert count > 0, "No matching buckets found in agent output."

    mse /= count
    expected_min_count = len(truth_distances) * 0.9
    assert count >= expected_min_count, (
        f"Agent output has {count} matching buckets, expected at least {expected_min_count}"
    )
    assert mse <= 0.01, f"MSE {mse:.6f} exceeds threshold 0.01"

    assert seen_buckets == set(truth_distances), (
        f"CSV bucket coverage is incorrect: missing {sorted(set(truth_distances) - seen_buckets)}, "
        f"unexpected {sorted(seen_buckets - set(truth_distances))}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
