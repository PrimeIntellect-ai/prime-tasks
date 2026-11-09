#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import re
from collections import defaultdict, Counter

ORIGINAL_RAW_LOGS = """[INFO] 2023-10-01T12:00:01Z - User: U001 performed Action: VIEW on Item: I001. Status: SUCCESS
[INFO] 2023-10-01T12:00:01Z - User: U001 performed Action: VIEW on Item: I001. Status: SUCCESS
[INFO] 2023-10-01T12:05:00Z - User: u001 performed Action: purCHASE on Item: i001. Status: Success
[ERROR] 2023-10-01T12:06:00Z - User: U002 performed Action: VIEW on Item: I002. Status: FAILED
[INFO] 2023-10-01T12:07:00Z - User: U002 performed Action: view on Item: I002. Status: SUCCESS
[INFO] 2023-10-01T12:08:00Z - User: U002 performed Action: CLICK on Item: I003. Status: SUCCESS
[INFO] 2023-10-01T12:09:00Z - User: U002 performed Action: VIEW on Item: I002. Status: SUCCESS
[INFO] 2023-10-01T12:10:00Z - User: U003 performed Action: LOGIN on Item: SYS. Status: SUCCESS
[INFO] 2023-10-01T12:11:00Z - User: U003 performed Action: LOGIN on Item: SYS. Status: SUCCESS
[INFO] 2023-10-01T12:12:00Z - User: U003 performed Action: logout on Item: sys. Status: success
[INFO] 2023-10-01T12:12:00Z - User: U003 performed Action: LOGOUT on Item: SYS. Status: SUCCESS
[WARNING] 2023-10-01T12:13:00Z - User: U004 performed Action: SEARCH on Item: I999. Status: FAILED
"""

def get_expected_features(raw_logs_path):
    if not os.path.isfile(raw_logs_path):
        return {}

    records = []
    pattern = re.compile(
        r'^\[.*?\]\s+(?P<timestamp>\S+)\s+-\s+User:\s+(?P<user_id>\S+)\s+performed\s+Action:\s+(?P<action>\S+)\s+on\s+Item:\s+(?P<item_id>\S+?)\.?\s+Status:\s+(?P<status>\S+)\s*$'
    )

    with open(raw_logs_path, 'r') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            match = pattern.match(line)
            if match:
                status = match.group('status').upper()
                if status == 'SUCCESS':
                    timestamp = match.group('timestamp')
                    user_id = match.group('user_id').upper()
                    action = match.group('action').upper()
                    item_id = match.group('item_id').upper()
                    records.append((timestamp, user_id, action, item_id))

    unique_records = list(set(records))
    user_data = defaultdict(list)
    for record in unique_records:
        user_data[record[1]].append(record)

    features = {}
    for user_id, user_records in user_data.items():
        action_counts = Counter(record[2] for record in user_records)
        sorted_actions = sorted(action_counts.items(), key=lambda x: (-x[1], x[0]))
        features[user_id] = {
            "total_actions": len(user_records),
            "unique_items": len(set(record[3] for record in user_records)),
            "most_frequent_action": sorted_actions[0][0]
        }

    return {key: features[key] for key in sorted(features.keys())}

def test_user_features_json():
    raw_logs_path = "/home/user/raw_logs.txt"
    json_path = "/home/user/user_features.json"

    assert os.path.isfile(raw_logs_path), f"The input file {raw_logs_path} does not exist."
    with open(raw_logs_path, 'r') as f:
        assert f.read() == ORIGINAL_RAW_LOGS, "The supplied raw log input was modified."

    assert os.path.isfile(json_path), f"The output file {json_path} does not exist."
    with open(json_path, 'r') as f:
        actual_data = json.load(f)

    expected_data = get_expected_features(raw_logs_path)

    assert list(actual_data.keys()) == list(expected_data.keys()), "User IDs (keys) in the output do not match the expected sorted normalized user IDs."

    for user_id, expected_features in expected_data.items():
        actual_features = actual_data[user_id]

        assert "total_actions" in actual_features, f"Missing 'total_actions' for user {user_id}"
        assert actual_features["total_actions"] == expected_features["total_actions"], f"Incorrect 'total_actions' for user {user_id}"

        assert "unique_items" in actual_features, f"Missing 'unique_items' for user {user_id}"
        assert actual_features["unique_items"] == expected_features["unique_items"], f"Incorrect 'unique_items' for user {user_id}"

        assert "most_frequent_action" in actual_features, f"Missing 'most_frequent_action' for user {user_id}"
        assert actual_features["most_frequent_action"] == expected_features["most_frequent_action"], f"Incorrect 'most_frequent_action' for user {user_id}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
