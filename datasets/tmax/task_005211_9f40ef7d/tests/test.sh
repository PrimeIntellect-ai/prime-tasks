#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import secrets
import stat
import subprocess
from datetime import datetime, timezone
from pathlib import Path


def parse_timestamp(ts):
    if isinstance(ts, int) or (isinstance(ts, str) and ts.isdigit()):
        return datetime.fromtimestamp(int(ts), tz=timezone.utc)
    else:
        # Handle ISO8601 string like "2023-10-01T15:30:00Z"
        return datetime.strptime(ts.replace("Z", "+0000"), "%Y-%m-%dT%H:%M:%S%z")


def compute_expected_summary(log_file):
    if not os.path.exists(log_file):
        return {}

    # service -> hour -> (timestamp, allocation)
    service_changes = {}

    with open(log_file, 'r') as f:
        for line in f:
            if not line.strip():
                continue
            entry = json.loads(line)
            alloc = entry.get("allocation")

            # 1. Validation Gate
            if alloc is None or alloc < 0 or alloc > 10000:
                continue

            ts_raw = entry.get("timestamp")
            dt = parse_timestamp(ts_raw)

            # 2. Time Alignment (only 2023-10-01)
            if dt.year == 2023 and dt.month == 10 and dt.day == 1:
                service = entry.get("service")
                hour = dt.hour

                if service not in service_changes:
                    service_changes[service] = {}

                # Keep latest chronologically occurring allocation
                if hour not in service_changes[service]:
                    service_changes[service][hour] = (dt, alloc)
                else:
                    if dt > service_changes[service][hour][0]:
                        service_changes[service][hour] = (dt, alloc)

    summary = {}
    for service, hours in service_changes.items():
        buckets = []
        current_alloc = 0
        for h in range(24):
            if h in hours:
                current_alloc = hours[h][1]
            buckets.append(current_alloc)

        summary[service] = {
            "min": min(buckets),
            "max": max(buckets),
            "avg": round(sum(buckets) / 24, 2)
        }

    return summary


def test_summary_json_exists():
    summary_path = '/home/user/summary.json'
    assert os.path.exists(summary_path), f"The file {summary_path} is missing."
    assert os.path.isfile(summary_path), f"The path {summary_path} is not a file."


def test_summary_json_content():
    summary_path = '/home/user/summary.json'
    log_path = '/home/user/config_changes.jsonl'

    assert os.path.exists(summary_path), f"{summary_path} does not exist."
    assert os.path.exists(log_path), f"{log_path} does not exist."

    with open(summary_path, 'r') as f:
        try:
            actual_summary = json.load(f)
        except json.JSONDecodeError:
            assert False, f"{summary_path} is not a valid JSON file."

    expected_summary = compute_expected_summary(log_path)

    # Check that the keys match exactly
    assert set(actual_summary.keys()) == set(expected_summary.keys()), \
        f"Expected services {list(expected_summary.keys())}, but got {list(actual_summary.keys())}."

    for service, expected_stats in expected_summary.items():
        actual_stats = actual_summary[service]

        assert actual_stats.get("min") == expected_stats["min"], \
            f"Service '{service}': expected min {expected_stats['min']}, got {actual_stats.get('min')}"

        assert actual_stats.get("max") == expected_stats["max"], \
            f"Service '{service}': expected max {expected_stats['max']}, got {actual_stats.get('max')}"

        # Float comparison for average
        expected_avg = expected_stats["avg"]
        actual_avg = actual_stats.get("avg")
        assert actual_avg is not None, f"Service '{service}': missing 'avg' key"
        assert abs(actual_avg - expected_avg) <= 0.01, \
            f"Service '{service}': expected avg {expected_avg}, got {actual_avg}"


def test_go_program_generates_summary_from_new_input():
    process_path = Path('/home/user/process.go')
    log_path = Path('/home/user/config_changes.jsonl')
    summary_path = Path('/home/user/summary.json')

    assert process_path.exists(), f"The file {process_path} is missing."
    assert stat.S_ISREG(process_path.lstat().st_mode), f"{process_path} must be a regular Go source file."

    original_log = log_path.read_bytes()
    original_summary = summary_path.read_bytes() if summary_path.exists() else None

    token = secrets.token_hex(6)
    service_a = f"api-動的-{token}"
    service_b = f"worker-🧪-{token}"
    a_early = secrets.randbelow(1500) + 100
    a_late = a_early + secrets.randbelow(1000) + 1
    a_mid = secrets.randbelow(2000) + 2500
    a_end = secrets.randbelow(1000) + 5000
    b_value = secrets.randbelow(3000) + 400

    entries = [
        {"timestamp": "2023-10-01T03:50:00Z", "service": service_a, "allocation": a_late},
        {"timestamp": "2023-10-01T03:10:00Z", "service": service_a, "allocation": a_early},
        {"timestamp": int(datetime(2023, 10, 1, 8, 0, tzinfo=timezone.utc).timestamp()), "service": service_a, "allocation": a_mid},
        {"timestamp": "2023-10-01T12:00:00Z", "service": service_a, "allocation": 10001},
        {"timestamp": "2023-10-01T20:45:00Z", "service": service_a, "allocation": a_end},
        {"timestamp": int(datetime(2023, 10, 1, 5, 30, tzinfo=timezone.utc).timestamp()), "service": service_b, "allocation": b_value},
        {"timestamp": "2023-10-01T07:00:00Z", "service": service_b, "allocation": -1},
        {"timestamp": "2023-09-30T23:59:59Z", "service": service_b, "allocation": 9999},
        {"timestamp": "2023-10-02T00:00:00Z", "service": service_a, "allocation": 1},
    ]

    try:
        with log_path.open('w', encoding='utf-8') as f:
            for entry in entries:
                f.write(json.dumps(entry, ensure_ascii=False) + '\n')

        if summary_path.exists():
            summary_path.unlink()

        result = subprocess.run(
            ['go', 'run', str(process_path)],
            cwd='/home/user',
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=60,
        )
        assert result.returncode == 0, \
            f"go run failed with exit code {result.returncode}:\n{result.stdout}\n{result.stderr}"
        assert process_path.exists() and stat.S_ISREG(process_path.lstat().st_mode), \
            f"{process_path} was not preserved as a regular file."
        assert summary_path.exists() and summary_path.is_file(), \
            "The Go program did not generate /home/user/summary.json."

        try:
            with summary_path.open('r', encoding='utf-8') as f:
                actual_summary = json.load(f)
        except json.JSONDecodeError as exc:
            assert False, f"The generated summary is not valid JSON: {exc}"

        expected_summary = compute_expected_summary(str(log_path))
        assert set(actual_summary.keys()) == set(expected_summary.keys()), \
            f"Expected services {list(expected_summary.keys())}, but got {list(actual_summary.keys())}."

        for service, expected_stats in expected_summary.items():
            actual_stats = actual_summary[service]
            assert actual_stats.get('min') == expected_stats['min'], \
                f"Service '{service}': expected min {expected_stats['min']}, got {actual_stats.get('min')}"
            assert actual_stats.get('max') == expected_stats['max'], \
                f"Service '{service}': expected max {expected_stats['max']}, got {actual_stats.get('max')}"
            actual_avg = actual_stats.get('avg')
            assert actual_avg is not None, f"Service '{service}': missing 'avg' key"
            assert abs(actual_avg - expected_stats['avg']) <= 0.01, \
                f"Service '{service}': expected avg {expected_stats['avg']}, got {actual_avg}"
    finally:
        log_path.write_bytes(original_log)
        if original_summary is None:
            if summary_path.exists():
                summary_path.unlink()
        else:
            summary_path.write_bytes(original_summary)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
