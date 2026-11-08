#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import glob
import re

def recompute_expected_outputs(data_dir):
    all_lines = []
    for filepath in glob.glob(os.path.join(data_dir, "*.csv")):
        with open(filepath, "r") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                parts = line.split(",")
                if len(parts) != 4:
                    continue

                timestamp, user_id, action, value = parts

                # Normalize action
                action = action.strip().lower()

                # Validate
                if not re.match(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$", timestamp):
                    continue
                if not re.match(r"^[A-Za-z0-9]{6}$", user_id):
                    continue
                if action not in ("purchase", "refund", "login"):
                    continue
                if not re.match(r"^\d+$", value):
                    continue

                normalized_line = f"{timestamp},{user_id},{action},{value}"
                all_lines.append(normalized_line)

    # Deduplicate
    unique_lines = list(set(all_lines))

    # Sort chronologically
    # Since timestamp is ISO 8601, string sorting works
    unique_lines.sort(key=lambda x: x.split(",")[0])

    cleaned = []
    anomalies = []

    baselines = {}

    for line in unique_lines:
        timestamp, user_id, action, value = line.split(",")
        value = int(value)

        if action in ("purchase", "refund"):
            if user_id in baselines:
                baseline = baselines[user_id]
                if value > 10 * baseline:
                    anomalies.append(line)
                else:
                    cleaned.append(line)
                    baselines[user_id] = value
            else:
                cleaned.append(line)
                baselines[user_id] = value
        else:
            # login action
            cleaned.append(line)

    return cleaned, anomalies

def test_script_exists_and_executable():
    script_path = "/home/user/etl_cleaner.sh"
    assert os.path.isfile(script_path), f"The script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"The script {script_path} is not executable."

def test_cleaned_csv_output():
    cleaned_path = "/home/user/cleaned.csv"
    assert os.path.isfile(cleaned_path), f"The output file {cleaned_path} does not exist."

    expected_cleaned, _ = recompute_expected_outputs("/home/user/data")

    with open(cleaned_path, "r") as f:
        actual_cleaned = [line.strip() for line in f if line.strip()]

    assert actual_cleaned == expected_cleaned, f"The contents of {cleaned_path} do not match the expected derived output."

def test_anomalies_csv_output():
    anomalies_path = "/home/user/anomalies.csv"
    assert os.path.isfile(anomalies_path), f"The output file {anomalies_path} does not exist."

    _, expected_anomalies = recompute_expected_outputs("/home/user/data")

    with open(anomalies_path, "r") as f:
        actual_anomalies = [line.strip() for line in f if line.strip()]

    assert actual_anomalies == expected_anomalies, f"The contents of {anomalies_path} do not match the expected derived output."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
