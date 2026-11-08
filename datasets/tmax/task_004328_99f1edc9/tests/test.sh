#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
from collections import defaultdict
import pytest

EXPECTED_EVENTS = (
    b'{"user_id": 101, "event_type": "query", "timestamp": "2023-01-01T10:00:00Z", "metadata": {"duration": 150.5, "status": "success"}}\n'
    b'{"user_id": 101, "event_type": "query", "timestamp": "2023-01-01T10:05:00Z", "metadata": {"duration": 200.0, "status": "success"}}\n'
    b'{"user_id": 101, "event_type": "click", "timestamp": "2023-01-01T10:06:00Z", "metadata": {"duration": 10.0, "status": "success"}}\n'
    b'{"user_id": 102, "event_type": "query", "timestamp": "2023-01-01T10:07:00Z", "metadata": {"duration": 300.25, "status": "success"}}\n'
    b'{"user_id": 102, "event_type": "query", "timestamp": "2023-01-01T10:08:00Z", "metadata": {"duration": 500.0, "status": "error"}}\n'
    b'{"user_id": 103, "event_type": "query", "timestamp": "2023-01-01T10:10:00Z", "metadata": {"duration": 45.1, "status": "success"}}\n'
    b'{"user_id": 103, "event_type": "query", "timestamp": "2023-01-01T10:11:00Z", "metadata": {"duration": 45.1, "status": "success"}}\n'
    b'{"user_id": 104, "event_type": "query", "timestamp": "2023-01-01T10:15:00Z", "metadata": {"duration": 300.25, "status": "success"}}\n'
)

def test_report_csv_matches_expected():
    """Test that the generated report.csv matches the expected aggregation output."""
    events_path = "/home/user/events.jsonl"
    report_path = "/home/user/report.csv"

    assert os.path.isfile(events_path), f"Input file not found: {events_path}"
    assert os.path.isfile(report_path), f"Output file not found: {report_path}"

    # Ensure the agent processed the supplied input rather than replacing or truncating it.
    with open(events_path, "rb") as f:
        actual_events = f.read()
    assert actual_events == EXPECTED_EVENTS, (
        f"Input file was modified: {events_path} must remain exactly as supplied"
    )

    # Recompute the expected output from the events.jsonl file
    stats = defaultdict(lambda: {"count": 0, "sum": 0.0})
    with open(events_path, 'r') as f:
        for i, line in enumerate(f):
            line = line.strip()
            if not line:
                continue
            try:
                ev = json.loads(line)
            except json.JSONDecodeError:
                pytest.fail(f"Line {i+1} in {events_path} is not valid JSON")

            event_type = ev.get("event_type")
            metadata = ev.get("metadata", {})
            status = metadata.get("status")
            duration = metadata.get("duration")
            user_id = ev.get("user_id")

            if event_type == "query" and status == "success":
                stats[user_id]["count"] += 1
                stats[user_id]["sum"] += duration

    results = []
    for uid, data in stats.items():
        avg = data["sum"] / data["count"]
        results.append((uid, data["count"], avg))

    # Sort by avg_duration_ms DESC, then user_id ASC
    results.sort(key=lambda x: (-x[2], x[0]))

    expected_lines = ["user_id,query_count,avg_duration_ms"]
    for uid, count, avg in results:
        expected_lines.append(f"{uid},{count},{avg:.2f}")

    # Read the actual report.csv
    with open(report_path, 'r') as f:
        actual_content = f.read().strip().split('\n')

    # Compare
    assert len(actual_content) == len(expected_lines), (
        f"Expected {len(expected_lines)} lines in report.csv, but found {len(actual_content)}."
    )

    for i, (actual_line, expected_line) in enumerate(zip(actual_content, expected_lines)):
        assert actual_line.strip() == expected_line, (
            f"Mismatch at line {i+1} in report.csv.\n"
            f"Expected: {expected_line}\n"
            f"Found:    {actual_line.strip()}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
