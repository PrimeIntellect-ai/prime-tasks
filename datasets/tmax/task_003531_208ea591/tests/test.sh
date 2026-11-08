#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import json
from datetime import datetime, timedelta

def test_translation_requests_file_exists():
    """Test that the final output file was created."""
    assert os.path.exists("/home/user/translation_requests.md"), "Output file /home/user/translation_requests.md is missing."

def test_translation_requests_content():
    """Test that the output file contains the correct content derived from the data."""

    # 1. Read and clean data
    events = set()
    with open("/home/user/logs/ui_events.csv", "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            ts = row.get("timestamp", "").strip()
            eid = row.get("element_id", "").strip()
            uid = row.get("user_id", "").strip()

            if not ts or not eid:
                continue

            # Deduplicate exact matches
            events.add((ts, uid, eid))

    # 2. Aggregate counts per day per element
    daily_counts = {}
    elements = set()
    for ts, uid, eid in events:
        # Parse date (ignore time)
        date_str = ts.split(" ")[0]
        if date_str not in daily_counts:
            daily_counts[date_str] = {}
        daily_counts[date_str][eid] = daily_counts[date_str].get(eid, 0) + 1
        elements.add(eid)

    # 3. Compute 3-day rolling average for 2023-10-15
    target_date_str = "2023-10-15"
    target_date = datetime.strptime(target_date_str, "%Y-%m-%d")

    rolling_averages = {}
    for eid in elements:
        total = 0
        days_counted = 3
        for i in range(3):
            d = target_date - timedelta(days=i)
            d_str = d.strftime("%Y-%m-%d")
            total += daily_counts.get(d_str, {}).get(eid, 0)

        rolling_averages[eid] = total / days_counted

    # 4. Sort to find top 3
    # Sort by rolling average descending, then element_id ascending
    sorted_elements = sorted(rolling_averages.items(), key=lambda x: (-x[1], x[0]))
    top_3_elements = [eid for eid, avg in sorted_elements[:3]]

    # 5. Map to loc keys
    with open("/home/user/loc/mapping.json", "r", encoding="utf-8") as f:
        mapping = json.load(f)

    top_3_keys = [mapping[eid] for eid in top_3_elements]
    keys_str = ", ".join(top_3_keys)

    # 6. Generate expected output
    with open("/home/user/templates/request_template.txt", "r", encoding="utf-8") as f:
        template = f.read()

    expected_output = template.replace("{KEYS}", keys_str)

    # 7. Verify actual output
    with open("/home/user/translation_requests.md", "r", encoding="utf-8") as f:
        actual_output = f.read()

    assert actual_output.strip() == expected_output.strip(), (
        f"The content of /home/user/translation_requests.md is incorrect.\n"
        f"Expected:\n{expected_output.strip()}\n\n"
        f"Actual:\n{actual_output.strip()}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
